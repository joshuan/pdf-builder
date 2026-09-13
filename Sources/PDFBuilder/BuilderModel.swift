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

    @Published var pages: [InputPage] = [] {
        didSet {
            guard !pages.contains(where: { $0.id == selectedPageID }) else { return }
            let previousIndex = oldValue.firstIndex(where: { $0.id == selectedPageID }) ?? 0
            selectedPageID = pages.isEmpty ? nil : pages[min(previousIndex, pages.count - 1)].id
        }
    }
    @Published var selectedPageID: InputPage.ID?
    @Published var pageFormat: PageFormat = .a4
    @Published var deleteSources = true
    @Published var alert: AppAlert?
    @Published var isSaving = false
    @Published var isDropTargeted = false
    @Published private var customOutputName: String?

    var outputName: String {
        get {
            customOutputName ?? pages.first.map {
                $0.sourceURL.deletingPathExtension().lastPathComponent
            } ?? ""
        }
        set { customOutputName = newValue }
    }

    var usesDefaultOutputName: Bool { customOutputName == nil }

    func resetOutputName() {
        customOutputName = nil
    }

    var sourceFileCount: Int {
        Set(pages.map(\.sourceURL)).count
    }

    var selectedPage: InputPage? {
        pages.first { $0.id == selectedPageID }
    }

    func moveSelection(by offset: Int) {
        guard !pages.isEmpty else { return }
        let index = pages.firstIndex { $0.id == selectedPageID } ?? 0
        selectedPageID = pages[min(max(index + offset, 0), pages.count - 1)].id
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
        if pages.isEmpty {
            resetOutputName()
            deleteSources = true
        }
    }

    func moveUp(_ page: InputPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }), index > 0 else { return }
        pages.swapAt(index, index - 1)
    }

    func moveDown(_ page: InputPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }), index < pages.count - 1 else { return }
        pages.swapAt(index, index + 1)
    }

    func movePages(from offsets: IndexSet, to destination: Int) {
        guard !isSaving else { return }
        pages.move(fromOffsets: offsets, toOffset: destination)
    }

    func clear() {
        pages = []
        pageFormat = .a4
        deleteSources = true
        resetOutputName()
    }

    var outputURL: URL? {
        try? OutputTransaction.outputURL(for: pages, baseName: outputName, deleteSources: deleteSources)
    }

    var outputNameError: String? {
        guard !pages.isEmpty else { return nil }
        do {
            _ = try OutputTransaction.outputURL(for: pages, baseName: outputName, deleteSources: deleteSources)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var canCreatePDF: Bool { !isSaving && outputURL != nil }

    var willReplaceExistingOutput: Bool {
        guard let outputURL,
              FileManager.default.fileExists(atPath: outputURL.path) else { return false }
        let sources = Set(pages.map { $0.sourceURL.standardizedFileURL })
        return !sources.contains(outputURL.standardizedFileURL)
    }

    func createPDF() {
        guard canCreatePDF else { return }

        isSaving = true

        var temporaryURL: URL?
        do {
            let finalURL = try OutputTransaction.outputURL(for: pages, baseName: outputName, deleteSources: deleteSources)
            let renderedURL = OutputTransaction.temporaryURL(nextTo: finalURL)
            temporaryURL = renderedURL

            try PDFComposer.write(pages: pages, format: pageFormat, to: renderedURL)
            try OutputTransaction.finalize(
                temporaryURL: renderedURL,
                pages: pages,
                outputURL: finalURL,
                deleteSources: deleteSources
            )

            let pageCount = pages.count
            let sourceCount = sourceFileCount
            let didDeleteSources = deleteSources
            Task {
                await CompletionNotifier.send(
                    outputName: finalURL.lastPathComponent,
                    pageCount: pageCount,
                    sourceCount: sourceCount,
                    deletedSources: didDeleteSources
                )
                NSApp.terminate(nil)
            }
        } catch {
            isSaving = false
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
            selectedPageID = nil
            resetOutputName()
            deleteSources = true
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
        NSApp.windows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
    }

    private func pageKey(_ page: InputPage) -> String {
        "\(page.sourceURL.path)#\(page.sourcePageIndex ?? -1)"
    }
}

enum CompletionNotifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(outputName: String, pageCount: Int, sourceCount: Int, deletedSources: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = "PDF Ready"
        let pageWord = pageCount == 1 ? "page" : "pages"
        let sourceWord = sourceCount == 1 ? "source" : "sources"
        let sourceAction = deletedSources ? "moved to the Trash" : "kept"
        content.body = "\(outputName) · \(pageCount) \(pageWord). \(sourceCount) \(sourceWord) \(sourceAction)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        // Wait for submission before quitting, even if notifications are denied.
        try? await UNUserNotificationCenter.current().add(request)
    }
}
