import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    private var authorizationRequested = false

    func notify(title: String, body: String) {
        Task {
            await postNotification(title: title, body: body)
        }
    }

    private func postNotification(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()

        if !authorizationRequested {
            authorizationRequested = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
