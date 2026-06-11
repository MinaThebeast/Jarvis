import SwiftUI

struct GoalsListView: View {
    let goals: [OrchestratorGoal]
    let accent: Color

    var body: some View {
        if goals.isEmpty {
            Text("No fleet goals")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(accent.opacity(0.4))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(goals.prefix(5)) { goal in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(statusColor(for: goal.status))
                            .frame(width: 4, height: 4)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.shortDescription)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(accent.opacity(0.65))
                                .lineLimit(1)
                            Text(goal.status.uppercased())
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(statusColor(for: goal.status).opacity(0.9))
                        }
                    }
                }
            }
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "active", "running":
            return .jarvisGreen
        case "paused", "planned", "pending":
            return .jarvisGold
        case "completed":
            return .jarvisCyan
        case "failed", "halted":
            return .jarvisRed
        default:
            return accent.opacity(0.5)
        }
    }
}
