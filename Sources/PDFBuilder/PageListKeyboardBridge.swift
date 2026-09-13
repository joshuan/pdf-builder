import AppKit
import QuickLookUI
import SwiftUI

/// Scope shortcuts to the focused page list (or its Quick Look panel), leaving
/// text editing and other windows to handle their own keys normally.
struct PageListKeyboardBridge: NSViewRepresentable {
    let isFocused: Bool
    let onMove: (Int) -> Void
    let onTogglePreview: () -> Void

    func makeNSView(context: Context) -> KeyboardView { KeyboardView() }

    func updateNSView(_ view: KeyboardView, context: Context) {
        view.isListFocused = isFocused
        view.onMove = onMove
        view.onTogglePreview = onTogglePreview
    }

    static func dismantleNSView(_ view: KeyboardView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class KeyboardView: NSView {
    var isListFocused = false
    var onMove: (Int) -> Void = { _ in }
    var onTogglePreview: () -> Void = {}
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let previewEvent = event.window is QLPreviewPanel && PageQuickLookController.shared.isVisible
            guard previewEvent || (event.window === self.window && (self.isListFocused || self.hasListFocus)) else { return event }
            if let editor = event.window?.firstResponder as? NSTextView, editor.isFieldEditor { return event }
            return self.handle(event) ? nil : event
        }
        PageQuickLookController.shared.focusList = { [weak self] in self?.focusList() }
        PageQuickLookController.shared.handleKeyEvent = { [weak self] event in
            self?.handle(event) ?? false
        }
        // SwiftUI's focus update may run before its List is attached, especially
        // when NSOpenPanel closes. Set the native responder once attachment ends.
        DispatchQueue.main.async { [weak self] in self?.focusList() }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private var listView: NSTableView? {
        func findTable(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for child in view.subviews {
                if let table = findTable(in: child) { return table }
            }
            return nil
        }
        return window?.contentView.flatMap { findTable(in: $0) }
    }

    private var hasListFocus: Bool {
        guard let table = listView, let responder = window?.firstResponder as? NSView else { return false }
        return responder === table || responder.isDescendant(of: table)
    }

    private func focusList() {
        guard let table = listView else { return }
        window?.makeFirstResponder(table)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        switch event.keyCode {
        case 125: onMove(1)
        case 126: onMove(-1)
        case 49:
            if !event.isARepeat { onTogglePreview() }
        case 53:
            guard PageQuickLookController.shared.isVisible else { return false }
            PageQuickLookController.shared.close()
        default: return false
        }
        return true
    }
}
