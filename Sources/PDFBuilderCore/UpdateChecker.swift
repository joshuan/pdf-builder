import Foundation

/// Checks GitHub for a release newer than the running build.
public enum UpdateChecker {
    /// The release workflow and install script must use the same repository.
    public static let repository = "joshuan/pdf-builder"

    /// The archive produced by `make package`.
    public static let archiveName = "PDFBuilder.zip"

    public struct Release: Equatable, Sendable {
        public var version: String
        public var page: URL
        public var download: URL?

        public init(version: String, page: URL, download: URL?) {
            self.version = version
            self.page = page
            self.download = download
        }
    }

    public enum Outcome: Equatable, Sendable {
        case upToDate
        case available(Release)
    }

    public enum Failure: LocalizedError, Equatable {
        case badResponse(Int)
        case malformed

        public var errorDescription: String? {
            switch self {
            case let .badResponse(code): "GitHub returned status \(code)."
            case .malformed: "The response from GitHub could not be read."
            }
        }
    }

    public static var runningVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    public static func check(
        currentVersion: String = runningVersion,
        session: URLSession = .shared
    ) async throws -> Outcome {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PDF Builder/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.badResponse(http.statusCode)
        }
        let release = try parse(data)
        return isNewer(release.version, than: currentVersion) ? .available(release) : .upToDate
    }

    /// GitHub's `latest` endpoint excludes drafts and prereleases.
    public static func parse(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadUrl: URL
            }

            let tagName: String
            let htmlUrl: URL
            let assets: [Asset]
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw Failure.malformed
        }
        return Release(
            version: normalized(payload.tagName),
            page: payload.htmlUrl,
            download: payload.assets.first { $0.name == archiveName }?.browserDownloadUrl
        )
    }

    /// Compares dotted versions numerically, including versions such as 1.10.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(of: candidate)
        let right = components(of: current)
        for index in 0..<max(left.count, right.count) {
            let candidatePart = index < left.count ? left[index] : 0
            let currentPart = index < right.count ? right[index] : 0
            if candidatePart != currentPart { return candidatePart > currentPart }
        }
        return false
    }

    /// Release tags carry a leading `v`; bundle versions do not.
    public static func normalized(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    private static func components(of version: String) -> [Int] {
        normalized(version).split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }
}

public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        guard now >= lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}
