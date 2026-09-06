import AppKit
import Foundation
import PDFBuilderCore

@MainActor
final class UpdateController {
    static let shared = UpdateController()

    private static let lastCheckKey = "lastUpdateCheck"
    private(set) var latest: UpdateChecker.Release?
    private var isInstalling = false

    func checkIfDue() async {
        let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        guard UpdateSchedule.isDue(lastCheck: lastCheck, now: Date()) else { return }
        await check(userInitiated: false)
    }

    func checkNow() async {
        await check(userInitiated: true)
    }

    func showLatest() async {
        if let latest {
            offer(latest)
        } else {
            await checkNow()
        }
    }

    func installLatest() async {
        guard let latest else {
            await checkNow()
            return
        }
        await install(latest)
    }

    private func check(userInitiated: Bool) async {
        let currentVersion = UpdateChecker.runningVersion
        do {
            let outcome = try await UpdateChecker.check(currentVersion: currentVersion)
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

            switch outcome {
            case .upToDate:
                if userInitiated {
                    UpdatePrompt.report("PDF Builder \(currentVersion) is the latest version.")
                }
            case let .available(release):
                latest = release
                if userInitiated {
                    offer(release, currentVersion: currentVersion)
                } else if await UpdateNotifier.post(
                    release: release,
                    currentVersion: currentVersion
                ) == false {
                    offer(release, currentVersion: currentVersion)
                }
            }
        } catch {
            // Automatic checks stay quiet when the computer is offline.
            if userInitiated {
                UpdatePrompt.report("Could not check for updates: \(error.localizedDescription)")
            }
        }
    }

    private func offer(
        _ release: UpdateChecker.Release,
        currentVersion: String = UpdateChecker.runningVersion
    ) {
        switch UpdatePrompt.ask(version: release.version, currentVersion: currentVersion) {
        case .install:
            Task { await install(release) }
        case .openPage:
            NSWorkspace.shared.open(release.page)
        case .later:
            break
        }
    }

    private func install(_ release: UpdateChecker.Release) async {
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }

        do {
            try await UpdateInstaller.install(release)
            NSApp.terminate(nil)
        } catch {
            UpdatePrompt.report("""
                Could not install the update: \(error.localizedDescription)

                PDF Builder \(UpdateChecker.runningVersion) is still installed and unharmed. \
                You can download \(release.version) from the release page instead.
                """)
        }
    }
}

@MainActor
enum UpdatePrompt {
    enum Answer {
        case install
        case openPage
        case later
    }

    static func ask(version: String, currentVersion: String) -> Answer {
        let alert = NSAlert()
        alert.messageText = "PDF Builder \(version) is available"
        alert.informativeText = "You have \(currentVersion). Installing replaces this copy and restarts the app."
        alert.addButton(withTitle: "Install and Restart")
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .install
        case .alertSecondButtonReturn: return .openPage
        default: return .later
        }
    }

    static func report(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Check for Updates"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
