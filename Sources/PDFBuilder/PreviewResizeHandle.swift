import AppKit
import PDFBuilderCore
import SwiftUI

struct PreviewResizeHandle: NSViewRepresentable {
    @Binding var width: Double

    func makeNSView(context: Context) -> PreviewResizeView {
        PreviewResizeView()
    }

    func updateNSView(_ view: PreviewResizeView, context: Context) {
        view.previewWidth = PreviewSizing.clampedWidth(width)
        view.onResize = { width = Double($0) }
    }
}

// Handle mouse events directly so the List does not start reordering this row.
final class PreviewResizeView: NSView {
    var previewWidth: CGFloat = PreviewSizing.defaultWidth
    var onResize: (CGFloat) -> Void = { _ in }
    private var dragStart: (x: CGFloat, width: CGFloat)?
    private var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag horizontally to resize all previews"
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Preview size")
        setAccessibilityHelp("Drag left or right to resize all page previews.")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragStart = (event.locationInWindow.x, previewWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        resize(to: dragStart.width + event.locationInWindow.x - dragStart.x)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: resize(to: previewWidth - 16)
        case 124: resize(to: previewWidth + 16)
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityValue() -> Any? { Int(previewWidth.rounded()) }

    override func accessibilityPerformIncrement() -> Bool {
        resize(to: previewWidth + 16)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        resize(to: previewWidth - 16)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered || dragStart != nil else { return }
        let color = dragStart == nil ? NSColor.tertiaryLabelColor : NSColor.controlAccentColor
        color.setFill()
        let grip = NSRect(x: bounds.midX - 1.5, y: bounds.midY - 16, width: 3, height: 32)
        NSBezierPath(roundedRect: grip, xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func resize(to width: CGFloat) {
        previewWidth = PreviewSizing.clampedWidth(width)
        onResize(previewWidth)
    }
}
