import SwiftUI

struct ActivityFeedView: View {
    let events: [ActivityEvent]
    let accent: Color

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if events.isEmpty {
                    Text("No activity yet")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(accent.opacity(0.35))
                } else {
                    ForEach(events.prefix(20)) { event in
                        activityRow(event)
                    }
                }
            }
        }
        .frame(maxHeight: 130)
    }

    private func activityRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: event.category.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(categoryColor(event.category))
                .frame(width: 12, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.message)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(accent.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(event.timestamp, style: .time)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(accent.opacity(0.35))
            }
        }
    }

    private func categoryColor(_ category: ActivityCategory) -> Color {
        switch category {
        case .tool:        return accent.opacity(0.7)
        case .fleet:       return .jarvisGreen
        case .deliverable: return .jarvisCyan
        case .workflow:    return .jarvisGold
        case .approval:    return .jarvisRed
        case .system:      return accent.opacity(0.5)
        case .autonomy:    return .jarvisGold
        }
    }
}

struct ActivityToastView: View {
    let event: ActivityEvent
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.category.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(categoryColor(event.category))

            Text(event.message)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(accent.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.jarvisPanel.opacity(0.85))
                .overlay(
                    Capsule()
                        .stroke(categoryColor(event.category).opacity(0.45), lineWidth: 1)
                )
        )
        .shadow(color: categoryColor(event.category).opacity(0.25), radius: 12)
        .frame(maxWidth: 420)
    }

    private func categoryColor(_ category: ActivityCategory) -> Color {
        switch category {
        case .tool:        return accent
        case .fleet:       return .jarvisGreen
        case .deliverable: return .jarvisCyan
        case .workflow:    return .jarvisGold
        case .approval:    return .jarvisRed
        case .system:      return accent.opacity(0.7)
        case .autonomy:    return .jarvisGold
        }
    }
}
