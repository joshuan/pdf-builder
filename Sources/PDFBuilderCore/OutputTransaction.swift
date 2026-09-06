import Foundation

public enum OutputTransactionError: LocalizedError {
    case missingFirstPage
    case trashFailed(String)
    case moveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingFirstPage:
            "The output PDF name could not be determined."
        case let .trashFailed(message):
            "The source files could not be moved to the Trash. \(message)"
        case let .moveFailed(message):
            "The finished PDF could not be placed next to the source files. \(message)"
        }
    }
}

public enum OutputTransaction {
    public static func outputURL(for pages: [InputPage]) throws -> URL {
        guard let firstPage = pages.first else { throw OutputTransactionError.missingFirstPage }
        return firstPage.sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(firstPage.sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")
    }

    public static func temporaryURL(nextTo outputURL: URL) -> URL {
        outputURL.deletingLastPathComponent()
            .appendingPathComponent(".pdf-builder-\(UUID().uuidString).tmp.pdf")
    }

    /// Moves every source (and an older file at the destination, if present) to
    /// the macOS Trash before putting the already-rendered PDF in its final place.
    /// If a step fails, moved files are restored whenever possible.
    public static func finalize(
        temporaryURL: URL,
        pages: [InputPage],
        outputURL: URL,
        fileManager: FileManager = .default,
        moveToBackup: ((URL) throws -> URL)? = nil
    ) throws {
        let sourceURLs = uniqueSourceURLs(from: pages)
        var targets = sourceURLs

        if fileManager.fileExists(atPath: outputURL.path), !targets.contains(outputURL.standardizedFileURL) {
            targets.append(outputURL.standardizedFileURL)
        }

        var moved: [(original: URL, backup: URL)] = []

        do {
            for target in targets where fileManager.fileExists(atPath: target.path) {
                let backupURL: URL
                if let moveToBackup {
                    backupURL = try moveToBackup(target)
                } else {
                    var resultingURL: NSURL?
                    try fileManager.trashItem(at: target, resultingItemURL: &resultingURL)
                    guard let resultingURL else {
                        throw OutputTransactionError.trashFailed(target.lastPathComponent)
                    }
                    backupURL = resultingURL as URL
                }
                moved.append((target, backupURL))
            }
        } catch {
            restore(moved.reversed(), fileManager: fileManager)
            if let transactionError = error as? OutputTransactionError {
                throw transactionError
            }
            throw OutputTransactionError.trashFailed(error.localizedDescription)
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            restore(moved.reversed(), fileManager: fileManager)
            throw OutputTransactionError.moveFailed(error.localizedDescription)
        }
    }

    private static func uniqueSourceURLs(from pages: [InputPage]) -> [URL] {
        var seen = Set<URL>()
        var result: [URL] = []
        for page in pages {
            let url = page.sourceURL.standardizedFileURL
            if seen.insert(url).inserted {
                result.append(url)
            }
        }
        return result
    }

    private static func restore<S: Sequence>(
        _ moved: S,
        fileManager: FileManager
    ) where S.Element == (original: URL, backup: URL) {
        for item in moved where !fileManager.fileExists(atPath: item.original.path) {
            try? fileManager.moveItem(at: item.backup, to: item.original)
        }
    }
}
