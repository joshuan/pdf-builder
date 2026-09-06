import Foundation
import PDFBuilderCore
import UserNotifications

/// Announces available releases through Notification Center.
enum UpdateNotifier {
    static let category = "update"
    static let installAction = "install"
    static let laterAction = "later"

    enum Action {
        case install
        case show
    }

    static func registerCategory() {
        let install = UNNotificationAction(
            identifier: installAction,
            title: "Install",
            options: [.foreground]
        )
        let later = UNNotificationAction(
            identifier: laterAction,
            title: "Later",
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: category,
                actions: [install, later],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    static func post(release: UpdateChecker.Release, currentVersion: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard await isAllowed(center) else { return false }

        let content = UNMutableNotificationContent()
        content.title = "PDF Builder \(release.version) is available"
        content.body = "You have \(currentVersion). Install it now, or leave this notification for later."
        content.categoryIdentifier = category

        let request = UNNotificationRequest(
            identifier: "update-\(release.version)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    static func action(for response: UNNotificationResponse) -> Action? {
        guard response.notification.request.content.categoryIdentifier == category else {
            return nil
        }

        return switch response.actionIdentifier {
        case installAction: .install
        case UNNotificationDefaultActionIdentifier: .show
        default: nil
        }
    }

    private static func isAllowed(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            true
        case .notDetermined:
            (try? await center.requestAuthorization(options: [.alert])) ?? false
        default:
            false
        }
    }
}
