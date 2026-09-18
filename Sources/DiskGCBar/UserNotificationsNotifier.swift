import Foundation
import UserNotifications
import DiskGCCore

final class UserNotificationsNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    private let fallback: Notifier
    private let onOpen: () -> Void

    // UNUserNotificationCenter traps when the process has no bundle identifier, which is
    // every run outside DiskGC.app — including `swift run`.
    private var bundled: Bool { Bundle.main.bundleIdentifier != nil }

    init(fallback: Notifier, onOpen: @escaping () -> Void) {
        self.fallback = fallback
        self.onOpen = onOpen
    }

    func requestAuthorization() {
        guard bundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func notify(title: String, message: String) {
        guard bundled else { return fallback.notify(title: title, message: message) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [fallback] error in
            guard error != nil else { return }
            fallback.notify(title: title, message: message)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async { self.onOpen() }
        completionHandler()
    }
}
