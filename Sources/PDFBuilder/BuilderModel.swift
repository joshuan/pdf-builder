import AppKit
import Foundation
import PDFBuilderCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class BuilderModel: ObservableObject {
    static let shared = BuilderModel()

    @Published var pages: [InputPage] = []
    @Published var pageFormat: PageFormat = .a4
    @Published var alert: AppAlert?
    @Published var isSaving = false
    @Published var isDropTargeted = false

    var sourceFileCount: Int {
        Set(pages.map(\.sourceURL)).count
    }

    func replaceFiles(with urls: [URL]) {
        importFiles(urls, replacing: true)
    }

    func addFiles(_ urls: [URL]) {
        importFiles(urls, replacing: false)
    }

    func chooseFiles(replacing: Bool = true) {
        let panel = NSOpenPanel()
        panel.title = replacing ? "Choose Images or PDFs" : "Add Files"
        panel.prompt = replacing ? "Choose" : "Add"
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK {
            importFiles(panel.urls, replacing: replacing)
        }
    }

    func remove(_ page: InputPage) {
        pages.removeAll { $0.id == page.id }
    }

    func moveUp(_ page: InputPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }), index > 0 else { return }
        pages.swapAt(index, index - 1)
    }

    func moveDown(_ page: InputPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }), index < pages.count - 1 else { return }
        pages.swapAt(index, index + 1)
    }

    func clear() {
        pages = []
        pageFormat = .a4
    }

    var outputURL: URL? {
        try? OutputTransaction.outputURL(for: pages)
    }

    var willReplaceExistingOutput: Bool {
        guard let outputURL,
              FileManager.default.fileExists(atPath: outputURL.path) else { return false }
        let sources = Set(pages.map { $0.sourceURL.standardizedFileURL })
        return !sources.contains(outputURL.standardizedFileURL)
    }

    func createPDF() {
        guard !pages.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        var temporaryURL: URL?
        do {
            let finalURL = try OutputTransaction.outputURL(for: pages)
            let renderedURL = OutputTransaction.temporaryURL(nextTo: finalURL)
            temporaryURL = renderedURL

            try PDFComposer.write(pages: pages, format: pageFormat, to: renderedURL)
            try OutputTransaction.finalize(
                temporaryURL: renderedURL,
                pages: pages,
                outputURL: finalURL
            )

            let pageCount = pages.count
            let sourceCount = sourceFileCount
            pages = []
            pageFormat = .a4
            CompletionNotifier.send(
                outputName: finalURL.lastPathComponent,
                pageCount: pageCount,
                sourceCount: sourceCount
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.windows.first(where: \.isVisible)?.performClose(nil)
            }
        } catch {
            if let temporaryURL {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            alert = AppAlert(
                title: "Could Not Create PDF",
                message: error.localizedDescription
            )
        }
    }

    private func importFiles(_ urls: [URL], replacing: Bool) {
        let result = DocumentLoader.load(urls: urls)
        let importedPages: [InputPage]

        if replacing {
            importedPages = result.pages
        } else {
            let existingKeys = Set(pages.map(pageKey))
            importedPages = pages + result.pages.filter { !existingKeys.contains(pageKey($0)) }
        }

        pages = importedPages
        pageFormat = DocumentLoader.recommendedFormat(for: importedPages)

        if !result.skippedFileNames.isEmpty {
            alert = AppAlert(
                title: "Some Files Were Skipped",
                message: result.skippedFileNames.joined(separator: "\n")
            )
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    private func pageKey(_ page: InputPage) -> String {
        "\(page.sourceURL.path)#\(page.sourcePageIndex ?? -1)"
    }
}

enum CompletionNotifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(outputName: String, pageCount: Int, sourceCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "PDF Ready"
        let pageWord = pageCount == 1 ? "page" : "pages"
        let sourceWord = sourceCount == 1 ? "source" : "sources"
        content.body = "\(outputName) · \(pageCount) \(pageWord). \(sourceCount) \(sourceWord) moved to the Trash."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
