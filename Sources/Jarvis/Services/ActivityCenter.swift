import Combine
import Foundation

enum ActivityCategory: String {
    case tool
    case fleet
    case deliverable
    case workflow
    case approval
    case system
    case autonomy

    var icon: String {
        switch self {
        case .tool:        return "wrench.and.screwdriver"
        case .fleet:       return "person.2.fill"
        case .deliverable: return "doc.fill"
        case .workflow:    return "arrow.triangle.branch"
        case .approval:    return "hand.raised.fill"
        case .system:      return "cpu"
        case .autonomy:    return "bolt.horizontal.circle"
        }
    }

    var sendsNotification: Bool {
        switch self {
        case .deliverable, .workflow, .approval, .autonomy:
            return true
        default:
            return false
        }
    }

    var notificationTitle: String {
        switch self {
        case .deliverable:
            return "Deliverable Created"
        case .workflow:
            return "Workflow Complete"
        case .approval:
            return "Approval Needed"
        case .autonomy:
            return "Fleet Autonomy"
        default:
            return "JARVIS"
        }
    }
}

struct ActivityEvent: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let category: ActivityCategory
    let message: String

    init(category: ActivityCategory, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.category = category
        self.message = message
    }
}

@MainActor
final class ActivityCenter: ObservableObject {
    static let shared = ActivityCenter()

    @Published private(set) var events: [ActivityEvent] = []
    @Published var toastEvent: ActivityEvent?

    private let maxEvents = 100
    private let notificationService: NotificationService
    private var toastTask: Task<Void, Never>?

    init(notificationService: NotificationService = .shared) {
        self.notificationService = notificationService
    }

    func post(_ category: ActivityCategory, _ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let event = ActivityEvent(category: category, message: trimmed)
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }

        presentToast(event)

        if category.sendsNotification {
            notificationService.notify(
                title: category.notificationTitle,
                body: trimmed
            )
        }
    }

    private func presentToast(_ event: ActivityEvent) {
        toastTask?.cancel()
        toastEvent = event
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.toastEvent?.id == event.id {
                self.toastEvent = nil
            }
        }
    }
}
