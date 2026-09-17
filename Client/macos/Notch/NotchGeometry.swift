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

// The sizes the user can set under Options › Notch Size, clamped to what the notch content can hold.
struct NotchLayout: Equatable {
    static let widthRange: ClosedRange<CGFloat> = 280...480
    static let heightRange: ClosedRange<CGFloat> = 156...260
    static let sideRange: ClosedRange<CGFloat> = 28...60
    static let zoomRange: ClosedRange<CGFloat> = 0.85...1.3
    static let artworkRange: ClosedRange<CGFloat> = 16...30
    static let `default` = NotchLayout(openSize: CGSize(width: 300, height: 166), sideExtension: 36, zoom: 1,
                                       restingArtwork: 24)

    // The open size the player needs at zoom 1, and the side width a resting icon needs.
    private static let contentMinimum = CGSize(width: 280, height: 156)
    private static let restingItemMinimum: CGFloat = 30

    let openSize: CGSize        // open notch, notch height included
    let sideExtension: CGFloat  // resting widening on each side
    let zoom: CGFloat           // text and icon size asked for
    let restingArtwork: CGFloat // artwork size on the closed notch, asked for

    init(openSize: CGSize, sideExtension: CGFloat, zoom: CGFloat, restingArtwork: CGFloat = 24) {
        self.openSize = CGSize(width: Self.clamp(openSize.width, Self.widthRange),
                               height: Self.clamp(openSize.height, Self.heightRange))
        self.sideExtension = Self.clamp(sideExtension, Self.sideRange)
        self.zoom = Self.clamp(zoom, Self.zoomRange)
        self.restingArtwork = Self.clamp(restingArtwork, Self.artworkRange)
    }

    // Closed-notch artwork size actually drawn: 2 pt clear of the notch's top and bottom, 3 pt of each side.
    func restingArtworkSize(notchHeight: CGFloat) -> CGFloat {
        min(restingArtwork, notchHeight - 4, sideExtension - 6)
    }

    // Zoom applied to the open content: lowered when the chosen size couldn't hold the content at that zoom.
    var contentScale: CGFloat {
        min(zoom, openSize.width / Self.contentMinimum.width, openSize.height / Self.contentMinimum.height)
    }

    // Zoom applied to the resting artwork and icons, lowered to fit the side width.
    var restingScale: CGFloat {
        min(zoom, sideExtension / Self.restingItemMinimum)
    }

    private static func clamp(_ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

// Where the notch panel goes (spec §4): the real notch, or a simulated pill centred at the top of a screen
// without one. Every rect shares the notch's horizontal centre and touches the top edge of the screen.
struct NotchGeometry: Equatable {
    static let simulatedWidth: CGFloat = 190        // pill width on a screen without a notch
    static let fallbackMenuBarHeight: CGFloat = 24  // pill height when the menu bar auto-hides

    let hasNotch: Bool
    let notch: CGRect
    let layout: NotchLayout

    init(screen: ScreenMetrics, layout: NotchLayout = .default) {
        self.layout = layout
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
        notch.insetBy(dx: -layout.sideExtension, dy: 0)
    }

    // The right widening while resting: the music control (level bars, next / play on hover).
    var restingTrailingZone: CGRect {
        CGRect(x: extended.maxX - layout.sideExtension, y: notch.minY, width: layout.sideExtension, height: notch.height)
    }

    var open: CGRect {
        let width = max(layout.openSize.width, extended.width)
        let height = max(layout.openSize.height, notch.height)
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
