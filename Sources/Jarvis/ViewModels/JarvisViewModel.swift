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

    // MARK: Services

    let openAI: OpenAIService
    let speech: SpeechRecognitionService
    let playback: AudioPlaybackService
    let conversationStore: ConversationStore
    let memoryStore: MemoryStore
    let voiceStore: VoiceStore
    let toolRegistry: ToolRegistry
    let actionSafety: ActionSafety
    let auditLog: ActionAuditLog

    private let maxAgentIterations = 5

    private var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?

    // MARK: Init

    init() {
        let memoryStore = MemoryStore()
        let conversationStore = ConversationStore()
        let actionSafety = ActionSafety()
        let auditLog = ActionAuditLog()
        let voiceStore = VoiceStore()

        self.voiceStore = voiceStore
        self.openAI = OpenAIService(voiceStore: voiceStore)
        self.speech = SpeechRecognitionService()
        self.playback = AudioPlaybackService()
        self.memoryStore = memoryStore
        self.conversationStore = conversationStore
        self.actionSafety = actionSafety
        self.auditLog = auditLog

        let openAI = self.openAI
        let screenCapture = ScreenCaptureService()

        self.toolRegistry = ToolRegistry([
            GetTimeTool(),
            RememberFactTool(memoryStore: memoryStore),
            RecallFactsTool(memoryStore: memoryStore),
            SeeScreenTool(openAI: openAI, screenCapture: screenCapture),
            SeeActiveWindowTool(openAI: openAI, screenCapture: screenCapture),
            AppControlTool(actionSafety: actionSafety, auditLog: auditLog),
            AppleScriptTool(actionSafety: actionSafety, auditLog: auditLog),
            SetVoiceTool(voiceStore: voiceStore)
        ])
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

        await speech.start()

        if speech.isActive {
            isMicListening = true
            statusMessage  = "LISTENING FOR WAKE WORD"
            phase          = .idle
        }
    }

    func stopJarvis() {
        speech.stop()
        playback.stop()
        isMicListening = false
        currentTask?.cancel()
        phase         = .idle
        statusMessage = "OFFLINE"
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

    private func handleAbort() {
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

    // MARK: Agent Loop

    private func runAgentLoop(userText: String) async throws -> String {
        var apiMessages = buildAPIMessages(userText: userText)
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

                    let output = await executeToolCall(call)
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

    private func buildAPIMessages(userText: String) -> [[String: Any]] {
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": JarvisConfig.systemPrompt]
        ]

        if !memoryStore.isEmpty {
            let recentFacts = memoryStore.all().suffix(20)
            let factsText = recentFacts.map(\.text).joined(separator: "\n")
            apiMessages.append([
                "role": "system",
                "content": "Known facts about the user and ongoing context:\n" + factsText
            ])
        }

        let context = messages.suffix(JarvisConfig.maxContextMessages)
        apiMessages += context.map { $0.openAIPayload }
        apiMessages.append(["role": "user", "content": userText])
        return apiMessages
    }

    private func executeToolCall(_ call: ToolCall) async -> String {
        guard let tool = toolRegistry.tool(named: call.name) else {
            return "Error: tool '\(call.name)' is not registered."
        }

        let arguments = ChatMessageBuilder.parseArguments(call.arguments)
        do {
            return try await tool.execute(arguments: arguments)
        } catch {
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
