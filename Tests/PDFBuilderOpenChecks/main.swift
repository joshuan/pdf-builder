import AppKit
import Foundation
import PDFBuilderCore

private struct CheckFailure: LocalizedError {
    let errorDescription: String?
}

@main
@MainActor
enum PDFBuilderOpenChecks {
    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let delegate = AppDelegate()
        let model = BuilderModel.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFBuilderOpenChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            model.clear()
            try? FileManager.default.removeItem(at: directory)
        }
        let first = try writeImage(directory.appendingPathComponent("page2.png"))
        let second = try writeImage(directory.appendingPathComponent("page10.png"))

        delegate.application(application, open: [second, first, first])
        try expect(model.pages.map(\.sourceURL) == [first, second], "A grouped Finder event lost, duplicated, or misordered files")
        try expect(model.selectedPageID == model.pages.first?.id, "The first imported page was not selected")
        model.moveSelection(by: 1)
        let selectedID = model.selectedPageID
        try expect(model.selectedPage?.sourceURL == second, "Down did not select the next page")
        model.moveSelection(by: 1)
        try expect(model.selectedPageID == selectedID, "Selection wrapped past the last page")
        model.moveUp(model.pages[1])
        try expect(model.selectedPageID == selectedID, "Reordering lost selection identity")
        model.moveSelection(by: 1)
        try expect(model.selectedPage?.sourceURL == first, "Selection did not follow the reordered list")
        model.remove(model.pages[1])
        try expect(model.selectedPageID == selectedID, "Removing selection did not select its nearest remaining neighbor")
        model.clear()
        try expect(model.selectedPage == nil && model.selectedPageID == nil, "Clearing left a stale selection")

        delegate.application(application, open: [first])
        delegate.application(application, open: [second])
        try expect(model.pages.map(\.sourceURL) == [first, second], "Separate Finder events replaced previously opened files")
        let originalIDs = Set(model.pages.map(\.id))
        model.outputName = "My combined document"
        model.deleteSources = false
        model.movePages(from: IndexSet(integer: 1), to: 0)
        delegate.application(application, open: [first, second])
        try expect(model.pages.map(\.sourceURL) == [second, first], "A repeated open event reset the page order")
        try expect(Set(model.pages.map(\.id)) == originalIDs, "A repeated open event recreated or duplicated pages")
        try expect(model.outputName == "My combined document" && !model.deleteSources, "An open event reset export settings")

        let pdfURL = directory.appendingPathComponent("multipage.pdf")
        try PDFComposer.write(pages: model.pages, format: .a4, to: pdfURL)
        delegate.application(application, open: [pdfURL])
        delegate.application(application, open: [pdfURL])
        try expect(model.pages.count == 4 && model.sourceFileCount == 3, "Opening a PDF lost existing images or duplicated PDF pages")
        try expect(model.pages.suffix(2).map(\.sourcePageIndex) == [0, 1], "PDF pages were not kept in document order")

        model.clear()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var error: NSString?
        for url in [first, second] {
            pasteboard.clearContents()
            try expect(pasteboard.writeObjects([url as NSURL]), "Could not write to the test pasteboard")
            delegate.makePDF(pasteboard, userData: nil, error: &error)
            try expect(error == nil, "Finder Service error: \(error ?? "unknown")")
        }
        try expect(error == nil && model.pages.map(\.sourceURL) == [first, second], "Separate Finder Service requests replaced pages")
        print("PDFBuilderOpenChecks: Finder events, duplicates, export settings, PDFs, Services, selection and keyboard navigation passed")
    }

    private static func writeImage(_ url: URL) throws -> URL {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 9,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckFailure(errorDescription: "Could not create a test image")
        }
        try data.write(to: url)
        return url.standardizedFileURL
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(errorDescription: message) }
    }
}
