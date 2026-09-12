import Foundation

public enum OutputTransactionError: LocalizedError {
    case missingFirstPage
    case invalidOutputName
    case outputIsDirectory
    case sourceWouldBeReplaced
    case trashFailed(String)
    case moveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingFirstPage:
            "The output PDF name could not be determined."
        case .invalidOutputName:
            "Enter a file name without slashes, colons, or control characters."
        case .outputIsDirectory:
            "A folder with this name already exists. Choose a different file name."
        case .sourceWouldBeReplaced:
            "Choose a different file name to keep the source PDF."
        case let .trashFailed(message):
            "The source files could not be moved to the Trash. \(message)"
        case let .moveFailed(message):
            "The finished PDF could not be placed next to the source files. \(message)"
        }
    }
}

public enum OutputTransaction {
    public static func outputURL(
        for pages: [InputPage],
        baseName: String? = nil,
        deleteSources: Bool = true
    ) throws -> URL {
        guard let firstPage = pages.first else { throw OutputTransactionError.missingFirstPage }
        let defaultName = firstPage.sourceURL.deletingPathExtension().lastPathComponent
        let name = (baseName ?? defaultName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains(":"),
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw OutputTransactionError.invalidOutputName
        }

        let outputURL = firstPage.sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(name)
            .appendingPathExtension("pdf")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw OutputTransactionError.outputIsDirectory
        }
        if !deleteSources {
            try ensureOutputPreservesSources(outputURL, sources: uniqueSourceURLs(from: pages), fileManager: .default)
        }
        return outputURL
    }

    public static func temporaryURL(nextTo outputURL: URL) -> URL {
        outputURL.deletingLastPathComponent()
            .appendingPathComponent(".pdf-builder-\(UUID().uuidString).tmp.pdf")
    }

    /// Moves sources to the Trash when requested, and backs up an older output
    /// before putting the already-rendered PDF in its final place.
    /// If a step fails, moved files are restored whenever possible.
    public static func finalize(
        temporaryURL: URL,
        pages: [InputPage],
        outputURL: URL,
        deleteSources: Bool = true,
        fileManager: FileManager = .default,
        moveToBackup: ((URL) throws -> URL)? = nil
    ) throws {
        let sourceURLs = uniqueSourceURLs(from: pages)
        if !deleteSources {
            try ensureOutputPreservesSources(outputURL, sources: sourceURLs, fileManager: fileManager)
        }
        var targets = deleteSources ? sourceURLs : []

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

    private static func ensureOutputPreservesSources(
        _ outputURL: URL,
        sources: [URL],
        fileManager: FileManager
    ) throws {
        let output = outputURL.standardizedFileURL.resolvingSymlinksInPath()
        let outputAttributes = try? fileManager.attributesOfItem(atPath: output.path)

        for sourceURL in sources {
            let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            if source == output {
                throw OutputTransactionError.sourceWouldBeReplaced
            }
            // File identity also catches case-insensitive paths and hard links.
            if let outputDevice = outputAttributes?[.systemNumber] as? NSNumber,
               let outputInode = outputAttributes?[.systemFileNumber] as? NSNumber,
               let sourceAttributes = try? fileManager.attributesOfItem(atPath: source.path),
               let sourceDevice = sourceAttributes[.systemNumber] as? NSNumber,
               let sourceInode = sourceAttributes[.systemFileNumber] as? NSNumber,
               outputDevice == sourceDevice, outputInode == sourceInode {
                throw OutputTransactionError.sourceWouldBeReplaced
            }
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
