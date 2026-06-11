import SwiftUI

// MARK: - Conversation / Transcript Display

struct ConversationView: View {
    let messages: [Message]
    let liveTranscript: String
    let phase: JarvisPhase

    @State private var showTranscript = false

    var body: some View {
        VStack(spacing: 0) {
            // Live transcript (what user is saying)
            if !liveTranscript.isEmpty && (phase.isListeningOrWake || phase.isProcessing) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundColor(.jarvisGreen)
                        .font(.system(size: 13, weight: .bold))
                    Text(liveTranscript.uppercased())
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.jarvisGreen)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.jarvisPanel.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.jarvisGreen.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(6)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .padding(.bottom, 8)
            }

            // Recent messages
            if !messages.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(messages.suffix(4)) { msg in
                            MessageBubble(message: msg)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxHeight: 220)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: liveTranscript)
        .animation(.easeInOut(duration: 0.3), value: messages.count)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message

    private var isUser: Bool { message.role == .user }
    private var accent: Color { isUser ? .jarvisBlue : .jarvisCyan }
    private var icon: String { isUser ? "person.fill" : "cpu" }
    private var label: String { isUser ? "YOU" : "JARVIS" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Label
                HStack(spacing: 6) {
                    if !isUser {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(accent)
                        Text(label)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.7))
                    } else {
                        Text(label)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.7))
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(accent)
                    }
                }

                // Content
                Text(message.content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(6)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accent.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(accent.opacity(0.25), lineWidth: 1)
                            )
                    )
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
