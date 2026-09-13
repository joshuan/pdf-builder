import Foundation
import PDFKit

/// Quick Look receives original images and one-page PDFs, so the selected row
/// can be inspected at full quality independently of the source PDF's page count.
public final class PagePreviewStore {
    private let directory: URL
    private var cachedURLs: [InputPage.ID: URL] = [:]

    public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        directory = temporaryDirectory.appendingPathComponent("PDFBuilderQuickLook-\(UUID().uuidString)", isDirectory: true)
    }

    deinit { clear() }

    public func previewURL(for page: InputPage) throws -> URL {
        guard let index = page.sourcePageIndex else { return page.sourceURL }
        if let cached = cachedURLs[page.id] { return cached }
        guard let source = PDFDocument(url: page.sourceURL),
              !source.isLocked,
              index >= 0, index < source.pageCount,
              let selected = source.page(at: index)?.copy() as? PDFPage else {
            throw PreviewError.unreadablePage(page.displayName)
        }
        let document = PDFDocument()
        document.insert(selected, at: 0)
        guard let data = document.dataRepresentation() else {
            throw PreviewError.unreadablePage(page.displayName)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(page.id.uuidString).pdf")
        try data.write(to: url, options: .atomic)
        cachedURLs[page.id] = url
        return url
    }

    public func clear() {
        cachedURLs.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum PreviewError: LocalizedError {
    case unreadablePage(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePage(let name): "Could not preview \(name)."
        }
    }
}
