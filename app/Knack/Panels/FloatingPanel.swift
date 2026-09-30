import AppKit
import SwiftUI

/// Borderless, non-activating floating panel (SPEC §5.1): the source app keeps focus and stays
/// frontmost, so its selection can be read and replaced.
final class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows one floating skill panel at a time, near the mouse pointer.
@MainActor
final class PanelPresenter {
    static let shared = PanelPresenter()

    private var panel: FloatingPanel?

    /// Orders the panel in *without* making it key, so a ⌘C fallback still reaches the source app.
    /// Call `focus()` once the selection has been read.
    func show<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) {
        close()
        let panel = FloatingPanel()
        let host = NSHostingController(rootView: content().frame(width: width))
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func focus() {
        panel?.makeKey()
    }

    /// Hides the panel so synthesized keystrokes go back to the source app.
    func hide() {
        panel?.orderOut(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - 40, y: mouse.y - size.height - 16)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        if origin.y < visible.minY + 8 { origin.y = min(mouse.y + 16, visible.maxY - size.height - 8) }
        panel.setFrameOrigin(origin)
    }
}
