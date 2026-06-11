import SwiftUI

struct ApprovalCardView: View {
    let pending: PendingApproval
    let accent: Color
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.jarvisRed)
                Text("APPROVAL REQUIRED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.jarvisRed)
                    .tracking(3)
            }

            Text(pending.summary)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(accent.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: 360)

            Text("Risk: \(pending.riskClass.label)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(riskColor)

            HStack(spacing: 16) {
                Button(action: onDeny) {
                    Text("DENY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.jarvisRed)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .stroke(Color.jarvisRed.opacity(0.6), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onApprove) {
                    Text("APPROVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.jarvisGreen)
                        )
                }
                .buttonStyle(.plain)
            }

            Text("Say \"approve\" or \"deny\"")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(accent.opacity(0.45))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.jarvisPanel.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.jarvisRed.opacity(0.45), lineWidth: 1)
                )
        )
        .shadow(color: Color.jarvisRed.opacity(0.2), radius: 18)
    }

    private var riskColor: Color {
        switch pending.riskClass {
        case .destructive:  return .jarvisRed
        case .money:        return .jarvisGold
        case .externalSend: return .jarvisCyan
        case .publish:      return .jarvisCyan
        case .legal:        return .jarvisGold
        case .digitalInternal: return accent.opacity(0.7)
        }
    }
}
