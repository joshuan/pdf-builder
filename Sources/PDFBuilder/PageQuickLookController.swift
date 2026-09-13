import AppKit
import PDFBuilderCore
import QuickLookUI

@MainActor
final class PageQuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    static let shared = PageQuickLookController()

    private var store = PagePreviewStore()
    private var selectedPage: InputPage?
    private var item: PreviewItem?
    private weak var panel: QLPreviewPanel?
    private weak var sourceWindow: NSWindow?
    var focusList: () -> Void = {}
    var handleKeyEvent: (NSEvent) -> Bool = { _ in false }
    var reportError: (Error) -> Void = { _ in }

    var isAvailable: Bool { selectedPage != nil }
    var isVisible: Bool { panel?.isVisible == true }

    func select(_ page: InputPage?) {
        guard selectedPage?.id != page?.id else { return }
        selectedPage = page
        item = nil
        guard page != nil else {
            close()
            store.clear()
            return
        }
        if isVisible { refresh() }
    }

    func toggle() {
        if isVisible {
            close()
            return
        }
        guard selectedPage != nil, prepareItem() else { return }
        sourceWindow = NSApp.mainWindow
        focusList()
        guard let preview = QLPreviewPanel.shared() else { return }
        preview.updateController()
        // orderFront does not transfer keyboard focus away from the page list.
        preview.orderFront(nil)
        sourceWindow?.makeKey()
        focusList()
    }

    func close() {
        panel?.orderOut(nil)
        if sourceWindow?.isVisible == true {
            sourceWindow?.makeKey()
            focusList()
        }
    }

    func shutdown() {
        close()
        store.clear()
        item = nil
        selectedPage = nil
        focusList = {}
        handleKeyEvent = { _ in false }
        reportError = { _ in }
    }

    func beginControl(_ panel: QLPreviewPanel) {
        self.panel = panel
        panel.dataSource = self
        panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = true
        panel.reloadData()
    }

    func endControl(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
        self.panel = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { item == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        item
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event else { return false }
        return handleKeyEvent(event)
    }

    private func refresh() {
        guard prepareItem() else {
            close()
            return
        }
        panel?.reloadData()
        panel?.currentPreviewItemIndex = 0
    }

    private func prepareItem() -> Bool {
        guard let selectedPage else { return false }
        do {
            item = PreviewItem(url: try store.previewURL(for: selectedPage), title: selectedPage.displayName)
            return true
        } catch {
            reportError(error)
            return false
        }
    }
}

private final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        previewItemURL = url
        previewItemTitle = title
    }
}
