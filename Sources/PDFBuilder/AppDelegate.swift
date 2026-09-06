import AppKit
@preconcurrency import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        UNUserNotificationCenter.current().delegate = self
        UpdateNotifier.registerCategory()
        CompletionNotifier.requestPermission()
        Task { await UpdateController.shared.checkIfDue() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        BuilderModel.shared.replaceFiles(with: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let action = UpdateNotifier.action(for: response) else { return }
        await MainActor.run { self.handle(action) }
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
            error.pointee = "Finder did not pass any selected files." as NSString
            return
        }

        BuilderModel.shared.replaceFiles(with: urls)
    }

    private func handle(_ action: UpdateNotifier.Action) {
        switch action {
        case .install:
            Task { await UpdateController.shared.installLatest() }
        case .show:
            NSApp.activate(ignoringOtherApps: true)
            Task { await UpdateController.shared.showLatest() }
        }
    }
}
