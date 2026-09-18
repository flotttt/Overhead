import AppKit

// Menu bar icon: one monochrome SF Symbol per mode, dimmed when disconnected; the app's mark in notch-only mode.
enum StatusIcon {
    // The O of the app icon (ring and ear cups, scripts/make_icon.swift's grid), as a template image.
    static let appMark: NSImage = {
        let scale: CGFloat = 0.25  // 100-unit grid; the mark spans x 14...86, y 21...79
        let image = NSImage(size: NSSize(width: 72 * scale, height: 58 * scale), flipped: true) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.translateX(by: -14, yBy: -21)
            transform.concat()
            NSColor.black.set()
            let ring = NSBezierPath(ovalIn: NSRect(x: 26, y: 26, width: 48, height: 48))
            ring.lineWidth = 10
            ring.stroke()
            NSBezierPath(roundedRect: NSRect(x: 14, y: 39, width: 15, height: 24), xRadius: 7.5, yRadius: 7.5).fill()
            NSBezierPath(roundedRect: NSRect(x: 71, y: 39, width: 15, height: 24), xRadius: 7.5, yRadius: 7.5).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Overhead"
        return image
    }()

    static func symbolName(for mode: SHCAmbientMode) -> String {
        switch mode {
        case .noiseCanceling: return "headphones.circle.fill"
        case .ambientSound: return "ear.and.waveform"
        default: return "headphones"
        }
    }

    static func image(connected: Bool, mode: SHCAmbientMode) -> NSImage? {
        let name = connected ? symbolName(for: mode) : "headphones"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Overhead")
            ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: "Overhead")
        image?.isTemplate = true // macOS tints it for light/dark menu bars
        return image
    }
}
