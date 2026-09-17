import CoreGraphics

// The NSScreen values NotchGeometry needs, copied out so this file stays AppKit-free (tested in LogicTests).
// Rects are in global screen coordinates (origin at the bottom-left of the primary screen).
struct ScreenMetrics: Equatable {
    var frame: CGRect
    var safeAreaTop: CGFloat        // NSScreen.safeAreaInsets.top (0 without a notch)
    var auxiliaryTopLeft: CGRect?   // NSScreen.auxiliaryTopLeftArea (nil without a notch)
    var auxiliaryTopRight: CGRect?  // NSScreen.auxiliaryTopRightArea
    var menuBarHeight: CGFloat      // frame.maxY - visibleFrame.maxY (0 when the menu bar auto-hides)
}

// Where the notch panel goes (spec §4): the real notch, or a simulated pill centred at the top of a screen
// without one. Every rect shares the notch's horizontal centre and touches the top edge of the screen.
struct NotchGeometry: Equatable {
    static let sideExtension: CGFloat = 36          // resting widening on each side (states 1-3)
    static let simulatedWidth: CGFloat = 190        // pill width on a screen without a notch
    static let fallbackMenuBarHeight: CGFloat = 24  // pill height when the menu bar auto-hides
    static let openSize = CGSize(width: 300, height: 166)

    let hasNotch: Bool
    let notch: CGRect

    init(screen: ScreenMetrics) {
        let top = screen.frame.maxY
        if screen.safeAreaTop > 0, let left = screen.auxiliaryTopLeft, let right = screen.auxiliaryTopRight,
           screen.frame.width - left.width - right.width > 0 {
            // Only the widths of the auxiliary areas are used, so their coordinate space doesn't matter.
            hasNotch = true
            notch = CGRect(x: screen.frame.minX + left.width, y: top - screen.safeAreaTop,
                           width: screen.frame.width - left.width - right.width, height: screen.safeAreaTop)
        } else {
            hasNotch = false
            let height = screen.menuBarHeight > 0 ? screen.menuBarHeight : Self.fallbackMenuBarHeight
            notch = CGRect(x: screen.frame.midX - Self.simulatedWidth / 2, y: top - height,
                           width: Self.simulatedWidth, height: height)
        }
    }

    // The notch widened on both sides, to hold the resting artwork / mode icons.
    var extended: CGRect {
        notch.insetBy(dx: -Self.sideExtension, dy: 0)
    }

    var open: CGRect {
        let width = max(Self.openSize.width, extended.width)
        let height = max(Self.openSize.height, notch.height)
        return CGRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height)
    }

    // Panel frame while resting; nil = hidden (nothing to show on a screen without a notch).
    func restingFrame(for state: NotchRestingState) -> CGRect? {
        switch state {
        case .empty: return hasNotch ? notch : nil
        default: return extended
        }
    }
}
