import AppKit
@preconcurrency import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        UNUserNotificationCenter.current().delegate = self
        CompletionNotifier.requestPermission()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        BuilderModel.shared.replaceFiles(with: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    @objc func makePDF(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []

        guard !urls.isEmpty else {
            error.pointee = "Finder не передал выбранные файлы." as NSString
            return
        }

        BuilderModel.shared.replaceFiles(with: urls)
    }
}
