import AppKit
import SwiftUI

// Borderless transparent panel above the menu bar (spec §4.3). It never becomes key or main, so the frontmost
// app keeps the keyboard; clicks still reach its controls through NotchHostingView.
final class NotchPanel: NSPanel {
    // A factory rather than a custom init: NSWindow subclasses that declare their own initializer must also
    // deal with NSWindow's required/unavailable initializers.
    static func make() -> NotchPanel {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// Reports the pointer entering or leaving the panel, whichever app is active.
final class NotchContainerView: NSView {
    var onHoverChange: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?() }
    override func mouseExited(with event: NSEvent) { onHoverChange?() }
}

// The panel is never key: without this, the first click would only be swallowed by the window.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
