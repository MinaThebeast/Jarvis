import SwiftUI
import Combine

// MARK: - Jarvis ViewModel (main coordinator)

@MainActor
final class JarvisViewModel: ObservableObject {

    // MARK: Published state

    @Published var phase: JarvisPhase = .idle
    @Published var messages: [Message] = []
    @Published var liveTranscript = ""
    @Published var audioLevel: Float = 0
    @Published var isConfigured = false
    @Published var statusMessage = "JARVIS ONLINE"
    @Published var isMicListening = false
    @Published var abortRequested = false
    @Published var orchestratorOnline = false
    @Published var spendSummary: OrchestratorSpendSummary?
    @Published var fleetAutonomyEnabled = false
    @Published var fleetGoals: [OrchestratorGoal] = []

    // MARK: Services

    let openAI: OpenAIService
    let orchestrator: OrchestratorClient
    let speech: SpeechRecognitionService
    let playback: AudioPlaybackService
    let conversationStore: ConversationStore
    let memoryStore: MemoryStore
    let voiceStore: VoiceStore
    let toolRegistry: ToolRegistry
    let actionSafety: ActionSafety
    let auditLog: ActionAuditLog
    let activityCenter: ActivityCenter
    let approvalService: ApprovalService
    let localAgentRunner: LocalAgentRunner
    let perceptionService: PerceptionService

    private let maxAgentIterations = 5

    private var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?
    private var orchestratorMonitorTask: Task<Void, Never>?
    private var lastAutonomyEventId = 0

    // MARK: Init

    init() {
        let memoryStore = MemoryStore()
        let conversationStore = ConversationStore()
        let actionSafety = ActionSafety()
        let auditLog = ActionAuditLog()
        let voiceStore = VoiceStore()
        let activityCenter = ActivityCenter.shared
        let approvalService = ApprovalService()
        let localAgentRunner = LocalAgentRunner()

        self.voiceStore = voiceStore
        self.openAI = OpenAIService(voiceStore: voiceStore)
        let orchestrator = OrchestratorClient()
        self.orchestrator = orchestrator
        self.speech = SpeechRecognitionService()
        self.playback = AudioPlaybackService()
        self.memoryStore = memoryStore
        self.conversationStore = conversationStore
        self.actionSafety = actionSafety
        self.auditLog = auditLog
        self.activityCenter = activityCenter
        self.approvalService = approvalService
        self.localAgentRunner = localAgentRunner

        let openAI = self.openAI
        let screenCapture = ScreenCaptureService()
        self.perceptionService = PerceptionService(screenCapture: screenCapture, openAI: openAI)

        self.toolRegistry = ToolRegistry([
            GetTimeTool(),
            RememberFactTool(memoryStore: memoryStore),
            RecallFactsTool(memoryStore: memoryStore),
            SeeScreenTool(openAI: openAI, screenCapture: screenCapture),
            SeeActiveWindowTool(openAI: openAI, screenCapture: screenCapture),
            AppControlTool(actionSafety: actionSafety, auditLog: auditLog),
            AppleScriptTool(actionSafety: actionSafety, auditLog: auditLog),
            ShellTool(actionSafety: actionSafety, auditLog: auditLog),
            TypeTextTool(actionSafety: actionSafety, auditLog: auditLog),
            PressKeysTool(actionSafety: actionSafety, auditLog: auditLog),
            MouseClickTool(actionSafety: actionSafety, auditLog: auditLog),
            HireAgentTool(orchestrator: orchestrator, activityCenter: activityCenter),
            DelegateTaskTool(
                orchestrator: orchestrator,
                activityCenter: activityCenter,
                localAgentRunner: localAgentRunner
            ),
            ListAgentsTool(orchestrator: orchestrator),
            PlanGoalTool(orchestrator: orchestrator),
            RunWorkflowTool(orchestrator: orchestrator, activityCenter: activityCenter),
            SaveDeliverableTool(auditLog: auditLog, activityCenter: activityCenter),
            SetVoiceTool(voiceStore: voiceStore)
        ])
        localAgentRunner.attach(viewModel: self, masterRegistry: toolRegistry)
        self.messages = conversationStore.load()

        checkConfiguration()
        bindServices()
    }

    // MARK: Configuration

    func checkConfiguration() {
        isConfigured = openAI.hasKey
    }

    func configure(apiKey: String) {
        openAI.saveAPIKey(apiKey)
        isConfigured = true
        Task { await startJarvis() }
    }

    // MARK: Lifecycle

    func startJarvis() async {
        guard isConfigured else { return }

        statusMessage  = "INITIALIZING SYSTEMS..."
        isMicListening = false

        speech.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleSpeechEvent(event)
            }
        }

        await refreshOrchestratorStatus()
        startOrchestratorMonitoring()

        await speech.start()

        if speech.isActive {
            isMicListening = true
            statusMessage  = "LISTENING FOR WAKE WORD"
            phase          = .idle
            activityCenter.post(.system, "JARVIS online")
        }
    }

    func stopJarvis() {
        orchestratorMonitorTask?.cancel()
        orchestratorMonitorTask = nil
        speech.stop()
        playback.stop()
        isMicListening = false
        currentTask?.cancel()
        perceptionService.stopMonitoring()
        phase         = .idle
        statusMessage = "OFFLINE"
    }

    // MARK: Orchestrator

    private func refreshOrchestratorStatus() async {
        orchestratorOnline = await orchestrator.health()
        guard orchestratorOnline else {
            spendSummary = nil
            fleetGoals = []
            return
        }

        spendSummary = try? await orchestrator.getSpend()
        if let status = try? await orchestrator.getAutonomy() {
            fleetAutonomyEnabled = status.enabled
        }
        fleetGoals = (try? await orchestrator.listGoals()) ?? []
        await pollAutonomyEvents()
    }

    private func pollAutonomyEvents() async {
        guard orchestratorOnline else { return }

        do {
            let events = try await orchestrator.autonomyEvents(since: lastAutonomyEventId)

            if lastAutonomyEventId == 0, !events.isEmpty {
                lastAutonomyEventId = events.map(\.id).max() ?? 0
                return
            }

            var lineToSpeak: String?

            for event in events {
                lastAutonomyEventId = max(lastAutonomyEventId, event.id)
                activityCenter.post(.autonomy, event.message)

                if lineToSpeak == nil, event.isHighSignal {
                    lineToSpeak = event.spokenLine
                }
            }

            if let lineToSpeak {
                await speakAutonomyReport(lineToSpeak)
            }
        } catch {
            return
        }
    }

    func setFleetAutonomyEnabled(_ enabled: Bool) {
        Task {
            do {
                let status = try await orchestrator.setAutonomy(enabled: enabled)
                fleetAutonomyEnabled = status.enabled
                activityCenter.post(
                    .system,
                    enabled ? "Fleet autonomy enabled" : "Fleet autonomy disabled"
                )
            } catch {
                activityCenter.post(
                    .system,
                    "Autonomy toggle failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func speakAutonomyReport(_ text: String) async {
        guard phase == .idle else { return }
        guard openAI.hasKey else { return }

        speech.pauseListening()
        defer {
            if speech.isActive {
                speech.resumeListening()
            }
        }

        do {
            let spoken = JarvisConfig.speechText(from: text)
            let audioData = try await openAI.textToSpeech(spoken)
            try await playback.play(data: audioData)
        } catch {
            return
        }
    }

    private func startOrchestratorMonitoring() {
        orchestratorMonitorTask?.cancel()
        orchestratorMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.refreshOrchestratorStatus()
            }
        }
    }

    // MARK: Speech Events

    private func handleSpeechEvent(_ event: SpeechEvent) {
        switch event {

        case .wakeWordDetected(let command) where command.isEmpty:
            abortRequested = false
            actionSafety.resetAbort()
            phase = .wakeDetected
            statusMessage = "READY FOR COMMAND"

        case .wakeWordDetected(let command):
            handleWake(command: command)

        case .commandCaptureStarted:
            phase = .listening
            statusMessage = "LISTENING..."

        case .commandCaptureCancelled:
            if phase.isListeningOrWake {
                phase = .idle
                statusMessage = "LISTENING FOR WAKE WORD"
                liveTranscript = ""
            }

        case .abortRequested:
            handleAbort()

        case .fleetHaltRequested:
            handleFleetHalt()

        case .approvalVoiceCommand(let approved):
            if approved {
                approvalService.approve()
            } else {
                approvalService.deny()
            }

        case .perceptionVoiceCommand(let enabled):
            setPerceptionEnabled(enabled)

        case .autonomyVoiceCommand(let enabled):
            setFleetAutonomyEnabled(enabled)

        case .audioLevel(let level):
            // Only pipe mic levels when we are actively listening/recording
            if phase.isListeningOrWake || phase == .idle {
                withAnimation(.easeOut(duration: 0.05)) {
                    audioLevel = level
                }
            }

        case .permissionDenied(let msg):
            phase         = .error(msg)
            statusMessage = "PERMISSION DENIED"

        case .recognitionError(let err):
            // Minor errors (silence, restarts) – don't surface
            let nsErr = err as NSError
            if nsErr.code == 1110 || nsErr.code == 216 { return }
            statusMessage = "RECOGNITION WARNING"
        }
    }

    func setPerceptionEnabled(_ enabled: Bool) {
        perceptionService.setEnabled(enabled)
        activityCenter.post(
            .system,
            enabled ? "Screen perception enabled" : "Screen perception disabled"
        )
    }

    private func handleFleetHalt() {
        handleAbort()
        activityCenter.post(.system, "Fleet halt requested — stopping local actions and orchestrator")
        Task {
            do {
                try await orchestrator.halt()
                _ = try? await orchestrator.setAutonomy(enabled: false)
                fleetAutonomyEnabled = false
                activityCenter.post(.system, "Fleet halted — autonomy disabled")
                await refreshOrchestratorStatus()
            } catch {
                activityCenter.post(.system, "Fleet halt failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleAbort() {
        if approvalService.pending != nil {
            approvalService.deny()
        }
        speech.listensForApproval = false
        abortRequested = true
        actionSafety.requestAbort()
        currentTask?.cancel()
        playback.stop()
        liveTranscript = ""
        phase = .idle
        statusMessage = "ACTIONS ABORTED"

        if speech.isActive {
            speech.resumeListening()
        }
    }

    private func handleWake(command: String) {
        currentTask?.cancel()
        abortRequested = false
        actionSafety.resetAbort()

        phase = .listening
        liveTranscript = command
        executeCommand(command)
    }

    private func executeCommand(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            phase         = .idle
            statusMessage = "LISTENING FOR WAKE WORD"
            return
        }

        currentTask = Task {
            abortRequested = false
            actionSafety.resetAbort()
            await processCommand(command)
        }
    }

    // MARK: Command Processing

    private func processCommand(_ userText: String) async {
        liveTranscript = userText
        phase          = .processing
        statusMessage  = "PROCESSING REQUEST..."
        speech.pauseListening()

        do {
            let reply = try await runAgentLoop(userText: userText)

            messages.append(Message(role: .user,      content: userText))
            messages.append(Message(role: .assistant, content: reply))
            conversationStore.save(messages)

            phase          = .responding(reply)
            statusMessage  = "JARVIS RESPONDING"
            audioLevel     = 0

            speech.pauseListening()

            let spokenText = JarvisConfig.speechText(from: reply)
            let audioData = try await openAI.textToSpeech(spokenText)
            try await playback.play(data: audioData)

            if speech.isActive {
                speech.resumeListening()
            }

        } catch is CancellationError {
            if speech.isActive { speech.resumeListening() }
            if abortRequested {
                phase = .idle
                statusMessage = "ACTIONS ABORTED"
            }
        } catch {
            if speech.isActive { speech.resumeListening() }
            let message = error.localizedDescription
            phase = .error(message)
            statusMessage = message.uppercased()
            liveTranscript = userText

            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !abortRequested {
                phase = .idle
                statusMessage = "LISTENING FOR WAKE WORD"
            }
        }

        if !Task.isCancelled && !abortRequested {
            phase         = .idle
            statusMessage = "LISTENING FOR WAKE WORD"
            audioLevel    = 0
        }
    }

    // MARK: Tool Loop

    func runToolLoop(
        systemPrompt: String,
        userText: String,
        toolRegistry: ToolRegistry,
        priorMessages: [[String: Any]] = []
    ) async throws -> String {
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages += priorMessages
        apiMessages.append(["role": "user", "content": userText])

        let tools = toolRegistry.isEmpty ? nil : toolRegistry.openAIToolsArray()

        for iteration in 0..<maxAgentIterations {
            try Task.checkCancellation()
            try actionSafety.checkAborted()

            if iteration > 0 {
                phase         = .processing
                statusMessage = "PROCESSING REQUEST..."
            }

            let result = try await openAI.chat(messages: apiMessages, tools: tools)

            if result.hasToolCalls, let toolCalls = result.toolCalls {
                apiMessages.append(ChatMessageBuilder.assistantMessage(result: result))

                for call in toolCalls {
                    try Task.checkCancellation()
                    try actionSafety.checkAborted()

                    phase = .actingTool(call.name)
                    statusMessage = call.name.hasPrefix("see_")
                        ? "ANALYZING VISION..."
                        : "EXECUTING \(call.name.uppercased())..."

                    let output = await executeToolCall(call, registry: toolRegistry)
                    apiMessages.append(
                        ChatMessageBuilder.toolResultMessage(
                            toolCallId: call.id,
                            content: output
                        )
                    )
                }
                continue
            }

            if let content = result.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                return content
            }

            throw OpenAIError.emptyResponse
        }

        throw OpenAIError.api("Agent loop exceeded maximum iterations.")
    }

    // MARK: Agent Loop

    private func runAgentLoop(userText: String) async throws -> String {
        var priorMessages: [[String: Any]] = []

        if !memoryStore.isEmpty {
            let recentFacts = memoryStore.all().suffix(20)
            let factsText = recentFacts.map(\.text).joined(separator: "\n")
            priorMessages.append([
                "role": "system",
                "content": "Known facts about the user and ongoing context:\n" + factsText
            ])
        }

        priorMessages += messages
            .suffix(JarvisConfig.maxContextMessages)
            .map { $0.openAIPayload }

        if let screenContext = perceptionService.contextMessage {
            priorMessages.append([
                "role": "system",
                "content": screenContext
            ])
        }

        return try await runToolLoop(
            systemPrompt: JarvisConfig.systemPrompt,
            userText: userText,
            toolRegistry: toolRegistry,
            priorMessages: priorMessages
        )
    }

    private func executeToolCall(_ call: ToolCall, registry: ToolRegistry) async -> String {
        guard let tool = registry.tool(named: call.name) else {
            return "Error: tool '\(call.name)' is not registered."
        }

        let arguments = ChatMessageBuilder.parseArguments(call.arguments)
        let risk = RiskClassifier.classify(tool: call.name, arguments: arguments)

        if risk.requiresApproval {
            let summary = RiskClassifier.summary(tool: call.name, arguments: arguments)
            activityCenter.post(.approval, "Approval needed: \(summary)")
            statusMessage = "AWAITING APPROVAL"
            phase = .processing

            speech.listensForApproval = true
            if speech.isActive {
                speech.resumeListening()
            }

            let approved = await approvalService.requestApproval(
                tool: call.name,
                summary: summary,
                risk: risk
            )

            speech.listensForApproval = false
            speech.pauseListening()

            if !approved {
                activityCenter.post(.approval, "Action denied: \(summary)")
                statusMessage = "PROCESSING REQUEST..."
                return "Action denied by user."
            }
        }

        activityCenter.post(.tool, "Running \(call.name)…")

        do {
            let result = try await tool.execute(arguments: arguments)
            activityCenter.post(.tool, "\(call.name) done")
            return result
        } catch {
            activityCenter.post(.tool, "\(call.name) failed")
            return "Error executing \(call.name): \(error.localizedDescription)"
        }
    }

    // MARK: Service Bindings

    private func bindServices() {
        // Mirror playback audio level to published level during TTS
        playback.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self, self.phase.isResponding else { return }
                withAnimation(.easeOut(duration: 0.04)) {
                    self.audioLevel = level
                }
            }
            .store(in: &cancellables)

        speech.$liveTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                guard let self else { return }
                guard self.phase.isListeningOrWake || self.phase.isProcessing else { return }
                self.liveTranscript = transcript
            }
            .store(in: &cancellables)
    }

    // MARK: Manual triggers (debug / button press)

    func manualListen() {
        guard phase == .idle else { return }
        phase         = .listening
        statusMessage = "LISTENING..."
        liveTranscript = ""
    }

    func clearHistory() {
        messages = []
        conversationStore.save(messages)
    }
}
