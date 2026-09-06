import AppKit
import Foundation

/// Downloads, verifies, atomically replaces, and relaunches the application.
public enum UpdateInstaller {
    public enum Failure: LocalizedError, Equatable {
        case noArchive
        case notWritable(String)
        case downloadFailed(Int)
        case unreadableBundle
        case notThisApp(String)
        case wrongVersion(expected: String, found: String)
        case damaged
        case toolFailed(String, Int32)

        public var errorDescription: String? {
            switch self {
            case .noArchive:
                "That release does not have a download attached yet."
            case let .notWritable(path):
                "\(path) is not writable. Install the update manually, or move PDF Builder somewhere you own."
            case let .downloadFailed(code):
                "The download failed with status \(code)."
            case .unreadableBundle:
                "The download did not contain an application."
            case let .notThisApp(identifier):
                "The download contains \(identifier), which is not PDF Builder."
            case let .wrongVersion(expected, found):
                "The download is version \(found), not \(expected)."
            case .damaged:
                "The downloaded application is damaged: its signature is invalid."
            case let .toolFailed(tool, status):
                "\(tool) failed with status \(status)."
            }
        }
    }

    /// Returns after the replacement is installed and a helper is waiting to
    /// relaunch it. The caller must terminate the current process afterwards.
    public static func install(_ release: UpdateChecker.Release) async throws {
        guard let source = release.download else { throw Failure.noArchive }

        let current = Bundle.main.bundleURL
        try requireWritable(current)

        // Staging on the app's volume keeps the final replacement atomic.
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: current,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: staging) }

        let archive = staging.appendingPathComponent(UpdateChecker.archiveName)
        try await download(source, to: archive)

        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])

        let replacement = try app(in: unpacked)
        try validate(replacement, expecting: release.version)
        try verifySignature(of: replacement)

        _ = try FileManager.default.replaceItemAt(current, withItemAt: replacement)
        try scheduleRelaunch(of: current)
    }

    public static func validate(
        _ app: URL,
        expecting version: String,
        identifier: String = Bundle.main.bundleIdentifier ?? "com.joshuan.pdf-builder"
    ) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: Any] else {
            throw Failure.unreadableBundle
        }

        let foundIdentifier = info["CFBundleIdentifier"] as? String ?? ""
        guard foundIdentifier == identifier else {
            throw Failure.notThisApp(foundIdentifier)
        }

        let foundVersion = info["CFBundleShortVersionString"] as? String ?? ""
        guard UpdateChecker.normalized(foundVersion) == UpdateChecker.normalized(version) else {
            throw Failure.wrongVersion(expected: version, found: foundVersion)
        }
    }

    public static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func requireWritable(_ bundle: URL) throws {
        let parent = bundle.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: bundle.path),
              FileManager.default.isWritableFile(atPath: parent.path) else {
            throw Failure.notWritable(parent.path)
        }
    }

    private static func download(_ url: URL, to destination: URL) async throws {
        let (temporary, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.downloadFailed(http.statusCode)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private static func app(in folder: URL) throws -> URL {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []
        guard let app = entries.first(where: { $0.pathExtension == "app" }) else {
            throw Failure.unreadableBundle
        }
        return app
    }

    private static func verifySignature(of app: URL) throws {
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw Failure.damaged
        }
    }

    private static func scheduleRelaunch(of app: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            open \(quoted(app.path))
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.toolFailed(tool, process.terminationStatus)
        }
    }
}
