import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFBuilderCore
import PDFKit
import UniformTypeIdentifiers

struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
enum PDFBuilderCoreChecks {
    static func main() throws {
        try naturalAlphabeticalSorting()
        try a4Recommendation()
        try automaticRecommendation()
        try composerWritesPagesAndSizes()
        try automaticPageAspectRatio()
        try outputNameAndFolder()
        try finalizeTransaction()
        print("PDFBuilderCoreChecks: 7 checks passed")
    }

    private static func naturalAlphabeticalSorting() throws {
        try withTemporaryDirectory { directory in
            let urls = ["page10.png", "page2.png", "page1.png"].map {
                directory.appendingPathComponent($0)
            }
            try expect(
                DocumentLoader.sorted(urls: urls).map(\.lastPathComponent)
                    == ["page1.png", "page2.png", "page10.png"],
                "Natural filename order is incorrect"
            )
        }
    }

    private static func a4Recommendation() throws {
        try withTemporaryDirectory { directory in
            let page = makePage(directory: directory, name: "scan.png", size: CGSize(width: 2100, height: 2970))
            try expect(DocumentLoader.recommendedFormat(for: [page]) == .a4, "A4-like page was not detected")
        }
    }

    private static func automaticRecommendation() throws {
        try withTemporaryDirectory { directory in
            let page = makePage(directory: directory, name: "wide.png", size: CGSize(width: 1600, height: 900))
            try expect(DocumentLoader.recommendedFormat(for: [page]) == .automatic, "Wide page should use Auto")
        }
    }

    private static func composerWritesPagesAndSizes() throws {
        try withTemporaryDirectory { directory in
            let portraitURL = try writePNG(directory: directory, name: "01.png", size: CGSize(width: 210, height: 297), color: .red)
            let landscapeURL = try writePNG(directory: directory, name: "02.png", size: CGSize(width: 160, height: 90), color: .blue)
            let loaded = DocumentLoader.load(urls: [landscapeURL, portraitURL])
            let outputURL = directory.appendingPathComponent("result.pdf")

            try PDFComposer.write(pages: loaded.pages, format: .a4, to: outputURL)

            let output = try require(PDFDocument(url: outputURL), "Could not open rendered PDF")
            try expect(output.pageCount == 2, "Rendered PDF has the wrong page count")
            let firstSize = try require(output.page(at: 0), "Missing first PDF page").bounds(for: .mediaBox).size
            let secondSize = try require(output.page(at: 1), "Missing second PDF page").bounds(for: .mediaBox).size
            try expect(abs(firstSize.width - PDFComposer.a4Size.width) < 0.5, "Portrait width is not A4")
            try expect(abs(firstSize.height - PDFComposer.a4Size.height) < 0.5, "Portrait height is not A4")
            try expect(
                abs(secondSize.width - PDFComposer.a4Size.height) < 0.5,
                "Landscape width is not A4 (got \(secondSize.width) × \(secondSize.height))"
            )
            try expect(
                abs(secondSize.height - PDFComposer.a4Size.width) < 0.5,
                "Landscape height is not A4 (got \(secondSize.width) × \(secondSize.height))"
            )
        }
    }

    private static func automaticPageAspectRatio() throws {
        try withTemporaryDirectory { directory in
            let page = makePage(directory: directory, name: "wide.png", size: CGSize(width: 16, height: 9))
            let size = PDFComposer.pageSize(for: page, format: .automatic)
            try expect(abs(size.width / size.height - 16.0 / 9.0) < 0.001, "Auto changed the aspect ratio")
            try expect(abs(size.width - PDFComposer.a4Size.height) < 0.001, "Auto did not normalize the long edge")
        }
    }

    private static func outputNameAndFolder() throws {
        try withTemporaryDirectory { directory in
            let first = makePage(directory: directory, name: "001 cover.png", size: CGSize(width: 210, height: 297))
            let second = makePage(directory: directory, name: "002.png", size: CGSize(width: 210, height: 297))
            let output = try OutputTransaction.outputURL(for: [first, second])
            try expect(output.lastPathComponent == "001 cover.pdf", "Output does not use the first page name")
            try expect(output.deletingLastPathComponent() == directory, "Output is not next to the first page")
        }
    }

    private static func finalizeTransaction() throws {
        try withTemporaryDirectory { directory in
            let firstURL = try writePNG(directory: directory, name: "01.png", size: CGSize(width: 21, height: 29), color: .red)
            let secondURL = try writePNG(directory: directory, name: "02.png", size: CGSize(width: 21, height: 29), color: .blue)
            let pages = DocumentLoader.load(urls: [firstURL, secondURL]).pages
            let outputURL = try OutputTransaction.outputURL(for: pages)
            let temporaryURL = OutputTransaction.temporaryURL(nextTo: outputURL)
            try PDFComposer.write(pages: pages, format: .a4, to: temporaryURL)
            let backupDirectory = directory.appendingPathComponent("backup", isDirectory: true)
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

            try OutputTransaction.finalize(
                temporaryURL: temporaryURL,
                pages: pages,
                outputURL: outputURL,
                moveToBackup: { source in
                    let destination = backupDirectory.appendingPathComponent(source.lastPathComponent)
                    try FileManager.default.moveItem(at: source, to: destination)
                    return destination
                }
            )

            try expect(FileManager.default.fileExists(atPath: outputURL.path), "Final PDF is missing")
            try expect(!FileManager.default.fileExists(atPath: firstURL.path), "First source was not backed up")
            try expect(!FileManager.default.fileExists(atPath: secondURL.path), "Second source was not backed up")
            try expect(FileManager.default.fileExists(atPath: backupDirectory.appendingPathComponent("01.png").path), "First backup is missing")
            try expect(FileManager.default.fileExists(atPath: backupDirectory.appendingPathComponent("02.png").path), "Second backup is missing")
        }
    }

    private static func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFBuilderChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private static func makePage(directory: URL, name: String, size: CGSize) -> InputPage {
        InputPage(
            sourceURL: directory.appendingPathComponent(name),
            displayName: name,
            imageSize: size,
            thumbnail: NSImage(size: CGSize(width: 10, height: 10))
        )
    }

    private static func writePNG(directory: URL, name: String, size: CGSize, color: NSColor) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = try require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ),
            "Could not create test image context"
        )
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let image = try require(context.makeImage(), "Could not render test image")
        let destination = try require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil),
            "Could not create PNG destination"
        )
        CGImageDestinationAddImage(destination, image, nil)
        try expect(CGImageDestinationFinalize(destination), "Could not encode test PNG")
        return url
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckFailure(message: message) }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }
}
