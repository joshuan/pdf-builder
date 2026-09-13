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
        try customOutputNames()
        try invalidOutputNames()
        try outputNameCannotReplaceDirectory()
        try finalizeTransaction()
        try keepsSourcesWhenRequested()
        try rejectsReplacingKeptSource()
        try restoresOutputWhenKeepingSources()
        try updateVersionComparison()
        try releaseParsing()
        try updateSchedule()
        try updateBundleValidation()
        try quickLookPagePreviews()
        print("PDFBuilderCoreChecks: 18 checks passed")
    }

    private static func quickLookPagePreviews() throws {
        try withTemporaryDirectory { directory in
            let first = try writePNG(directory: directory, name: "portrait.png", size: CGSize(width: 210, height: 297), color: .red)
            let second = try writePNG(directory: directory, name: "landscape.png", size: CGSize(width: 160, height: 90), color: .blue)
            let images = DocumentLoader.load(urls: [first, second]).pages
            let sourceURL = directory.appendingPathComponent("source.pdf")
            try PDFComposer.write(pages: images, format: .automatic, to: sourceURL)
            let source = try require(PDFDocument(url: sourceURL), "Missing source PDF")
            source.page(at: 1)?.rotation = 90
            try expect(source.write(to: sourceURL), "Could not set test page rotation")
            let original = try Data(contentsOf: sourceURL)
            let pages = DocumentLoader.load(urls: [sourceURL]).pages
            let store = PagePreviewStore(temporaryDirectory: directory)
            let firstURL = try store.previewURL(for: pages[0])
            let secondURL = try store.previewURL(for: pages[1])
            try expect(firstURL != secondURL, "Separate PDF rows share a preview")
            let cachedURL = try store.previewURL(for: pages[1])
            try expect(cachedURL == secondURL, "Preview cache was not reused")
            let firstPreview = try require(PDFDocument(url: firstURL), "Unreadable first preview")
            let secondPreview = try require(PDFDocument(url: secondURL), "Unreadable second preview")
            try expect(firstPreview.pageCount == 1 && secondPreview.pageCount == 1, "Quick Look included extra PDF pages")
            try expect(firstPreview.page(at: 0)?.bounds(for: .mediaBox) == source.page(at: 0)?.bounds(for: .mediaBox), "Wrong first page preview")
            try expect(secondPreview.page(at: 0)?.bounds(for: .mediaBox) == source.page(at: 1)?.bounds(for: .mediaBox), "Wrong second page preview")
            try expect(secondPreview.page(at: 0)?.rotation == 90, "Quick Look lost page rotation")
            let imageURL = try store.previewURL(for: images[0])
            try expect(imageURL == images[0].sourceURL, "An image preview used a thumbnail instead of its original")
            store.clear()
            try expect(!FileManager.default.fileExists(atPath: firstURL.path), "Temporary preview was not removed")
            let currentSource = try Data(contentsOf: sourceURL)
            try expect(currentSource == original, "Quick Look modified the source PDF")
            try expect(FileManager.default.fileExists(atPath: first.path), "Quick Look cleanup deleted an image")
        }
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
            let outputURL = try OutputTransaction.outputURL(for: pages, baseName: "Combined pages")
            let previousOutput = Data("previous PDF".utf8)
            try previousOutput.write(to: outputURL)
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
            let savedOutput = try require(PDFDocument(url: outputURL), "Custom-named output is not a PDF")
            try expect(savedOutput.pageCount == 2, "Custom-named output lost pages")
            let oldOutput = try Data(contentsOf: backupDirectory.appendingPathComponent("Combined pages.pdf"))
            try expect(oldOutput == previousOutput, "The previous custom-named output was not backed up")
        }
    }

    private static func keepsSourcesWhenRequested() throws {
        for replacingOutput in [false, true] {
            try withTemporaryDirectory { directory in
                let sourceURL = try writePNG(directory: directory, name: "source.png", size: CGSize(width: 21, height: 29), color: .red)
                let original = try Data(contentsOf: sourceURL)
                let pages = DocumentLoader.load(urls: [sourceURL]).pages
                let outputURL = try OutputTransaction.outputURL(for: pages, deleteSources: false)
                let previousOutput = Data("previous output".utf8)
                if replacingOutput { try previousOutput.write(to: outputURL) }
                let temporaryURL = OutputTransaction.temporaryURL(nextTo: outputURL)
                try PDFComposer.write(pages: pages, format: .a4, to: temporaryURL)
                let backupURL = directory.appendingPathComponent("output.backup")
                var backedUp: [URL] = []

                try OutputTransaction.finalize(
                    temporaryURL: temporaryURL,
                    pages: pages,
                    outputURL: outputURL,
                    deleteSources: false,
                    moveToBackup: { source in
                        backedUp.append(source)
                        try FileManager.default.moveItem(at: source, to: backupURL)
                        return backupURL
                    }
                )

                let keptSource = try Data(contentsOf: sourceURL)
                try expect(keptSource == original, "Keeping sources changed the original file")
                let output = try require(PDFDocument(url: outputURL), "Keeping sources did not produce a PDF")
                try expect(output.pageCount == 1, "Keeping sources lost output pages")
                try expect(backedUp == (replacingOutput ? [outputURL] : []), "Keeping sources moved an unexpected file")
                if replacingOutput {
                    let backup = try Data(contentsOf: backupURL)
                    try expect(backup == previousOutput, "Keeping sources lost the previous output")
                }
            }
        }
    }

    private static func rejectsReplacingKeptSource() throws {
        try withTemporaryDirectory { directory in
            let page = makePage(directory: directory, name: "Original.pdf", size: CGSize(width: 210, height: 297))
            let original = Data("original source".utf8)
            try original.write(to: page.sourceURL)
            let hardLink = directory.appendingPathComponent("Hard link.pdf")
            let symbolicLink = directory.appendingPathComponent("Symbolic link.pdf")
            try FileManager.default.linkItem(at: page.sourceURL, to: hardLink)
            try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: page.sourceURL)
            var destinations = [page.sourceURL, hardLink, symbolicLink]
            let caseVariant = directory.appendingPathComponent("original.pdf")
            if FileManager.default.fileExists(atPath: caseVariant.path) { destinations.append(caseVariant) }

            let defaultOutput = try OutputTransaction.outputURL(for: [page])
            try expect(defaultOutput == page.sourceURL, "Default delete mode no longer permits replacing an input PDF")
            let temporaryURL = OutputTransaction.temporaryURL(nextTo: page.sourceURL)
            let rendered = Data("rendered PDF".utf8)
            try rendered.write(to: temporaryURL)

            for destination in destinations {
                try expectSourceProtection {
                    _ = try OutputTransaction.outputURL(
                        for: [page],
                        baseName: destination.deletingPathExtension().lastPathComponent,
                        deleteSources: false
                    )
                }
                var backupCalled = false
                try expectSourceProtection {
                    try OutputTransaction.finalize(
                        temporaryURL: temporaryURL,
                        pages: [page],
                        outputURL: destination,
                        deleteSources: false,
                        moveToBackup: { source in
                            backupCalled = true
                            return source
                        }
                    )
                }
                try expect(!backupCalled, "A protected source reached the Trash operation")
                let keptSource = try Data(contentsOf: page.sourceURL)
                let keptTemporary = try Data(contentsOf: temporaryURL)
                try expect(keptSource == original, "A name collision changed the protected source")
                try expect(keptTemporary == rendered, "A name collision consumed the rendered file")
            }
        }
    }

    private static func restoresOutputWhenKeepingSources() throws {
        try withTemporaryDirectory { directory in
            let page = makePage(directory: directory, name: "source.png", size: CGSize(width: 210, height: 297))
            let sourceData = Data("original source".utf8)
            try sourceData.write(to: page.sourceURL)
            let outputURL = try OutputTransaction.outputURL(for: [page], deleteSources: false)
            let oldOutput = Data("previous PDF".utf8)
            try oldOutput.write(to: outputURL)
            let backupURL = directory.appendingPathComponent("previous.backup")
            do {
                try OutputTransaction.finalize(
                    temporaryURL: directory.appendingPathComponent("missing.tmp.pdf"),
                    pages: [page],
                    outputURL: outputURL,
                    deleteSources: false,
                    moveToBackup: { source in
                        try expect(source == outputURL, "Rollback preparation attempted to move a kept source")
                        try FileManager.default.moveItem(at: source, to: backupURL)
                        return backupURL
                    }
                )
                throw CheckFailure(message: "A missing rendered file did not fail")
            } catch OutputTransactionError.moveFailed {
                let restoredOutput = try Data(contentsOf: outputURL)
                let keptSource = try Data(contentsOf: page.sourceURL)
                try expect(restoredOutput == oldOutput, "Failure did not restore the previous output")
                try expect(keptSource == sourceData, "Failure changed a kept source")
            }
        }
    }

    private static func expectSourceProtection(_ operation: () throws -> Void) throws {
        do {
            try operation()
            throw CheckFailure(message: "An output was allowed to replace a kept source")
        } catch OutputTransactionError.sourceWouldBeReplaced {
            // Both validation and final placement must protect sources.
        }
    }

    private static func customOutputNames() throws {
        try withTemporaryDirectory { directory in
            let first = makePage(directory: directory, name: "001.png", size: CGSize(width: 210, height: 297))
            let otherDirectory = directory.appendingPathComponent("other", isDirectory: true)
            let second = makePage(directory: otherDirectory, name: "002.png", size: CGSize(width: 210, height: 297))
            let cases = [
                ("My document", "My document.pdf"),
                ("My document.txt", "My document.txt.pdf"),
                ("  Итоговый файл  ", "Итоговый файл.pdf"),
                ("Report.v2", "Report.v2.pdf")
            ]
            for (input, expected) in cases {
                let output = try OutputTransaction.outputURL(for: [first, second], baseName: input)
                try expect(output.lastPathComponent == expected, "Unexpected custom file name: \(output.lastPathComponent)")
                try expect(output.deletingLastPathComponent() == directory, "Custom name changed the output folder")
            }
            let reordered = try OutputTransaction.outputURL(for: [second, first])
            try expect(reordered.lastPathComponent == "002.pdf", "Default output name did not follow the first page")
            try expect(reordered.deletingLastPathComponent() == otherDirectory, "Output folder did not follow the first page")
            let customReordered = try OutputTransaction.outputURL(for: [second, first], baseName: "Keep this name")
            try expect(customReordered.lastPathComponent == "Keep this name.pdf", "Reordering changed the custom output name")
            try expect(customReordered.deletingLastPathComponent() == otherDirectory, "Custom output did not follow the first page folder")
        }
    }

    private static func invalidOutputNames() throws {
        try withTemporaryDirectory { directory in
            let page = makePage(directory: directory, name: "source.png", size: CGSize(width: 210, height: 297))
            for name in ["", "   ", ".", "..", "../outside", "/tmp/out.pdf", "sub/file", "bad:name", "a\u{0}b", "a\nb"] {
                do {
                    _ = try OutputTransaction.outputURL(for: [page], baseName: name)
                    throw CheckFailure(message: "Invalid output name was accepted: \(name.debugDescription)")
                } catch OutputTransactionError.invalidOutputName {
                    // Validation must fail before rendering or moving any source files.
                }
            }
        }
    }

    private static func outputNameCannotReplaceDirectory() throws {
        try withTemporaryDirectory { directory in
            let page = makePage(directory: directory, name: "source.png", size: CGSize(width: 210, height: 297))
            let existingDirectory = directory.appendingPathComponent("Existing.pdf", isDirectory: true)
            try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
            do {
                _ = try OutputTransaction.outputURL(for: [page], baseName: "Existing")
                throw CheckFailure(message: "Output name was allowed to replace a directory")
            } catch OutputTransactionError.outputIsDirectory {
                try expect(FileManager.default.fileExists(atPath: existingDirectory.path), "Name validation removed a directory")
            }
        }
    }

    private static func updateVersionComparison() throws {
        try expect(UpdateChecker.isNewer("1.2.4", than: "1.2.3"), "A patch update was missed")
        try expect(UpdateChecker.isNewer("1.10.0", than: "1.9.0"), "Versions were compared as text")
        try expect(!UpdateChecker.isNewer("v1.2.3", than: "1.2.3"), "Equivalent tag and bundle versions differ")
        try expect(!UpdateChecker.isNewer("1.2", than: "1.2.0"), "A missing version component did not count as zero")
    }

    private static func releaseParsing() throws {
        let payload = """
        {
          "tag_name": "v1.4.0",
          "html_url": "https://github.com/joshuan/pdf-builder/releases/tag/v1.4.0",
          "assets": [
            {
              "name": "PDFBuilder.zip",
              "browser_download_url": "https://github.com/joshuan/pdf-builder/releases/download/v1.4.0/PDFBuilder.zip"
            }
          ]
        }
        """
        let release = try UpdateChecker.parse(Data(payload.utf8))
        try expect(release.version == "1.4.0", "The release version was not normalized")
        try expect(release.download?.lastPathComponent == UpdateChecker.archiveName, "The release archive was not found")
    }

    private static func updateSchedule() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        try expect(UpdateSchedule.isDue(lastCheck: nil, now: now), "The first update check was not due")
        try expect(
            !UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-3600), now: now),
            "A second check was allowed too early"
        )
        try expect(
            UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-UpdateSchedule.interval - 1), now: now),
            "A daily update check was not due"
        )
        try expect(
            UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(UpdateSchedule.interval), now: now),
            "A future clock value blocked update checks"
        )
    }

    private static func updateBundleValidation() throws {
        try withTemporaryDirectory { directory in
            let app = directory.appendingPathComponent("PDF Builder.app", isDirectory: true)
            let contents = app.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

            try writeInfoPlist(
                at: contents.appendingPathComponent("Info.plist"),
                identifier: "com.joshuan.pdf-builder",
                version: "1.3.0"
            )
            try UpdateInstaller.validate(
                app,
                expecting: "v1.3.0",
                identifier: "com.joshuan.pdf-builder"
            )

            try expectUpdateFailure(.notThisApp("com.joshuan.pdf-builder")) {
                try UpdateInstaller.validate(
                    app,
                    expecting: "1.3.0",
                    identifier: "com.example.different"
                )
            }
            try expectUpdateFailure(.wrongVersion(expected: "2.0.0", found: "1.3.0")) {
                try UpdateInstaller.validate(
                    app,
                    expecting: "2.0.0",
                    identifier: "com.joshuan.pdf-builder"
                )
            }
            try expect(
                UpdateInstaller.quoted("/tmp/it's here.app") == "'/tmp/it'\\''s here.app'",
                "The relaunch helper did not quote an apostrophe safely"
            )
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

    private static func writeInfoPlist(at url: URL, identifier: String, version: String) throws {
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier,
            "CFBundleShortVersionString": version
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }

    private static func expectUpdateFailure(
        _ expected: UpdateInstaller.Failure,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            throw CheckFailure(message: "Expected update validation to fail with \(expected)")
        } catch let failure as UpdateInstaller.Failure {
            try expect(failure == expected, "Unexpected update failure: \(failure)")
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckFailure(message: message) }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }
}
