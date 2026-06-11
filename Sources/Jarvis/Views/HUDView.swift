import SwiftUI

// MARK: - Main HUD View

struct HUDView: View {
    @EnvironmentObject var vm: JarvisViewModel
    @ObservedObject var activityCenter: ActivityCenter
    @ObservedObject var approvalService: ApprovalService
    @ObservedObject var perceptionService: PerceptionService

    @State private var statusBlink = true
    @State private var elapsedTime: Date = Date()
    @State private var uptimeString = "00:00:00"
    @State private var systemLoad: [CGFloat] = [0.3, 0.5, 0.4, 0.6, 0.45]
    @State private var systemLoadIdx = 0

    private var phase: JarvisPhase { vm.phase }
    private var accent: Color { phase.accentColor }

    var body: some View {
        ZStack {
            // LAYER 1: Background
            BackgroundView(phase: phase)

            // LAYER 2: Particle field
            ParticleFieldView(phase: phase)
                .allowsHitTesting(false)

            // LAYER 3: Outer status rings
            StatusRingsView(phase: phase)
                .ignoresSafeArea()

            // LAYER 4: Main content
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 40)
                    .padding(.top, 20)

                Spacer()

                centerPiece

                Spacer()

                bottomSection
                    .padding(.horizontal, 40)
                    .padding(.bottom, 24)
            }

            // LAYER 5: System side panels
            HStack {
                leftPanel
                    .frame(width: 200)
                    .padding(.leading, 50)
                    .padding(.vertical, 80)
                Spacer()
                rightPanel
                    .frame(width: 200)
                    .padding(.trailing, 50)
                    .padding(.vertical, 80)
            }
        }
        .onAppear {
            startTimers()
            Task { await vm.startJarvis() }
        }
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // Left: System label
            VStack(alignment: .leading, spacing: 2) {
                Text("STARK TECHNOLOGY DIVISION")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(accent.opacity(0.5))
                    .tracking(3)
                Text("JARVIS v1.0.3")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                    .tracking(2)
            }

            Spacer()

            // Center: Status badge
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: accent, radius: 6)
                    .opacity(statusBlink ? 1 : 0.2)

                Text(phase.label)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                    .tracking(4)
                    .animation(.easeInOut(duration: 0.3), value: phase.label)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(accent.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(accent.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: accent.opacity(0.2), radius: 15)

            Spacer()

            // Right: Clock & uptime
            VStack(alignment: .trailing, spacing: 2) {
                Text(uptimeString)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                Text("SYSTEM UPTIME")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(accent.opacity(0.5))
                    .tracking(3)
            }
        }
    }

    // MARK: Center Piece

    private var centerPiece: some View {
        ZStack {
            // Waveform behind reactor
            WaveformView(phase: phase, audioLevel: vm.audioLevel)
                .opacity(phase.isActive ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.5), value: phase.isActive)

            // Arc reactor
            ArcReactorView(phase: phase, audioLevel: vm.audioLevel)

            if let toast = activityCenter.toastEvent {
                VStack {
                    Spacer()
                    ActivityToastView(event: toast, accent: accent)
                        .padding(.bottom, 100)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .animation(.easeInOut(duration: 0.35), value: toast.id)
            }

            if let pending = approvalService.pending {
                ApprovalCardView(
                    pending: pending,
                    accent: accent,
                    onApprove: { approvalService.approve() },
                    onDeny: { approvalService.deny() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(2)
            }
        }
    }

    // MARK: Bottom Section

    private var bottomSection: some View {
        VStack(spacing: 16) {
            // Status message
            Text(vm.statusMessage)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(accent.opacity(0.6))
                .tracking(4)
                .animation(.easeInOut(duration: 0.3), value: vm.statusMessage)

            // Linear waveform
            LinearWaveformView(phase: phase, audioLevel: vm.audioLevel)
                .frame(maxWidth: 600)
                .opacity(phase.isActive ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.4), value: phase.isActive)

            // Conversation
            ConversationView(
                messages: vm.messages,
                liveTranscript: vm.liveTranscript,
                phase: phase
            )
            .frame(maxWidth: 700)

            // Divider
            HStack {
                Rectangle()
                    .fill(accent.opacity(0.2))
                    .frame(height: 1)
                Text("◆")
                    .foregroundColor(accent.opacity(0.4))
                    .font(.system(size: 8))
                Rectangle()
                    .fill(accent.opacity(0.2))
                    .frame(height: 1)
            }

            // Mic indicator
            HStack(spacing: 8) {
                Image(systemName: vm.isMicListening ? "mic.fill" : "mic.slash.fill")
                    .foregroundColor(vm.isMicListening ? .jarvisGreen : .jarvisRed)
                    .font(.system(size: 11))
                Text(vm.isMicListening ? "MICROPHONE ACTIVE" : "MICROPHONE OFFLINE")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(vm.isMicListening ? .jarvisGreen.opacity(0.7) : .jarvisRed.opacity(0.7))
                    .tracking(2)
            }
        }
    }

    // MARK: Left Panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            panelHeader("SYSTEM STATUS")
            statusRow("NEURAL CORE",    value: "ONLINE",  ok: true)
            statusRow("API LINK",       value: "SECURE",  ok: vm.isConfigured)
            statusRow("VOICE ENGINE",   value: vm.isMicListening ? "ACTIVE" : "STANDBY", ok: vm.isMicListening)
            statusRow(
                "PERCEPTION",
                value: perceptionService.enabled ? "ON" : "OFF",
                ok: perceptionService.enabled
            )
            statusRow(
                "AUTONOMY",
                value: vm.fleetAutonomyEnabled ? "ON" : "OFF",
                ok: vm.fleetAutonomyEnabled
            )
            statusRow("MEMORY",         value: "\(vm.messages.count * 2) KB", ok: true)
            statusRow("ENCRYPTION",     value: "AES-256", ok: true)

            Spacer()

            panelHeader("ACTIVITY")
            ActivityFeedView(events: activityCenter.events, accent: accent)

            panelHeader("GOALS")
            GoalsListView(goals: vm.fleetGoals, accent: accent)

            panelHeader("CONTEXT")
            Text("\(vm.messages.count) exchanges logged")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(accent.opacity(0.5))

            if perceptionService.enabled, let summary = perceptionService.latestSummary {
                Text(summary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(accent.opacity(0.45))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Right Panel

    private var rightPanel: some View {
        VStack(alignment: .trailing, spacing: 18) {
            panelHeader("DIAGNOSTICS")
            statusRow(
                "ORCHESTRATOR",
                value: vm.orchestratorOnline ? "ONLINE" : "OFFLINE",
                ok: vm.orchestratorOnline
            )
            metricRow("LATENCY",  value: "—")
            metricRow("MODEL",    value: "GPT-4o")
            metricRow("SPEND",    value: vm.spendSummary?.hudLabel ?? "—")
            metricRow("TTS",      value: vm.voiceStore.openAIVoiceName)
            metricRow("LANG",     value: "EN-US")
            metricRow("TEMP",     value: "0.7")

            perceptionToggle

            autonomyToggle

            voiceToggle

            Spacer()
            panelHeader("PHASE")
            Text(phase.label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(accent)
        }
    }

    // MARK: Panel Helpers

    private func panelHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.5))
                .tracking(4)
            Rectangle()
                .fill(accent.opacity(0.25))
                .frame(height: 1)
        }
    }

    private func statusRow(_ label: String, value: String, ok: Bool) -> some View {
        HStack {
            Circle()
                .fill(ok ? Color.jarvisGreen : Color.jarvisRed)
                .frame(width: 5, height: 5)
                .shadow(color: ok ? .jarvisGreen : .jarvisRed, radius: 3)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(accent.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(ok ? .jarvisGreen : .jarvisRed)
        }
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Spacer()
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(accent.opacity(0.5))
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.8))
        }
    }

    private var perceptionToggle: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("PERCEPTION")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.5))
                .tracking(4)

            Toggle(isOn: Binding(
                get: { perceptionService.enabled },
                set: { vm.setPerceptionEnabled($0) }
            )) {
                Text(perceptionService.enabled ? "Watching" : "Off")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(accent.opacity(0.7))
            }
            .toggleStyle(.switch)
            .frame(width: 160)
        }
    }

    private var autonomyToggle: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("AUTONOMY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.5))
                .tracking(4)

            Toggle(isOn: Binding(
                get: { vm.fleetAutonomyEnabled },
                set: { vm.setFleetAutonomyEnabled($0) }
            )) {
                Text(vm.fleetAutonomyEnabled ? "Autonomous" : "Off")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(accent.opacity(0.7))
            }
            .toggleStyle(.switch)
            .frame(width: 160)
            .disabled(!vm.orchestratorOnline)
        }
    }

    private var voiceToggle: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("VOICE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.5))
                .tracking(4)

            Picker("Voice", selection: Binding(
                get: { vm.voiceStore.voiceKey },
                set: { vm.voiceStore.setVoice($0) }
            )) {
                Text("Female").tag("female")
                Text("Male").tag("male")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }

    // MARK: Timers

    private func startTimers() {
        elapsedTime = Date()

        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                statusBlink.toggle()
            }
        }

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let elapsed = Int(Date().timeIntervalSince(elapsedTime))
            let h = elapsed / 3600
            let m = (elapsed % 3600) / 60
            let s = elapsed % 60
            uptimeString = String(format: "%02d:%02d:%02d", h, m, s)
        }
    }
}
