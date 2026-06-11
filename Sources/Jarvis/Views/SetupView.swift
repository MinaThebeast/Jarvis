import SwiftUI

// MARK: - API Key Setup View

struct SetupView: View {
    @EnvironmentObject var vm: JarvisViewModel
    @State private var apiKey  = ""
    @State private var isValid = false
    @State private var showKey = false
    @State private var ringRotation: Double = 0
    @State private var pulse: Double = 1.0

    var body: some View {
        ZStack {
            Color.jarvisDark.ignoresSafeArea()
            HexGridCanvas(color: .jarvisBlue, opacity: 0.3).ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Animated Logo
                ZStack {
                    Circle()
                        .stroke(Color.jarvisBlue.opacity(0.2), lineWidth: 1)
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(ringRotation))

                    Circle()
                        .stroke(Color.jarvisBlue.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [12, 8]))
                        .frame(width: 130, height: 130)
                        .rotationEffect(.degrees(-ringRotation * 1.5))

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.9), Color.jarvisBlue, Color.jarvisBlue.opacity(0.2)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 55
                            )
                        )
                        .frame(width: 90, height: 90)
                        .scaleEffect(pulse)
                        .shadow(color: .jarvisBlue, radius: 30)
                }
                .onAppear {
                    withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                        ringRotation = 360
                    }
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        pulse = 1.06
                    }
                }

                // Title
                VStack(spacing: 8) {
                    Text("J.A.R.V.I.S")
                        .font(.system(size: 42, weight: .ultraLight, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(12)

                    Text("JUST A RATHER VERY INTELLIGENT SYSTEM")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.jarvisBlue.opacity(0.7))
                        .tracking(4)

                    Rectangle()
                        .fill(Color.jarvisBlue.opacity(0.4))
                        .frame(height: 1)
                        .padding(.horizontal, 60)
                        .padding(.top, 4)
                }

                // API Key Input
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OPENAI API KEY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.jarvisBlue.opacity(0.7))
                            .tracking(3)

                        HStack {
                            Group {
                                if showKey {
                                    TextField("sk-...", text: $apiKey)
                                } else {
                                    SecureField("sk-...", text: $apiKey)
                                }
                            }
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .textFieldStyle(.plain)
                            .onChange(of: apiKey) { newVal in
                                isValid = newVal.hasPrefix("sk-") && newVal.count > 20
                            }

                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundColor(.jarvisBlue.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.jarvisPanel.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isValid ? Color.jarvisGreen.opacity(0.6) : Color.jarvisBlue.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }

                    Text("Your key is stored securely in the macOS Keychain and never leaves your device.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.jarvisBlue.opacity(0.5))
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("VOICE PROFILE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.jarvisBlue.opacity(0.7))
                            .tracking(3)

                        Picker("Voice", selection: Binding(
                            get: { vm.voiceStore.voiceKey },
                            set: { vm.voiceStore.setVoice($0) }
                        )) {
                            Text("Female (nova)").tag("female")
                            Text("Male (onyx)").tag("male")
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Activate Button
                    Button {
                        guard isValid else { return }
                        vm.configure(apiKey: apiKey)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.fill")
                            Text("INITIALIZE JARVIS")
                                .tracking(4)
                        }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(isValid ? Color.jarvisDark : Color.jarvisBlue.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            isValid
                                ? Color.jarvisBlue
                                : Color.jarvisPanel.opacity(0.3)
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.jarvisBlue.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: isValid ? .jarvisBlue.opacity(0.4) : .clear, radius: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                    .animation(.easeInOut(duration: 0.3), value: isValid)
                }
                .frame(maxWidth: 480)

                Spacer()

                Text("v1.0.3  ·  STARK TECHNOLOGY")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.jarvisBlue.opacity(0.3))
                    .tracking(4)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 60)
        }
    }
}
