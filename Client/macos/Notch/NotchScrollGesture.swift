import CoreGraphics

// A scroll event, copied out of NSEvent so the gesture logic stays AppKit-free (tested in LogicTests).
struct ScrollSample {
    enum Phase {
        case none      // mouse wheel, no gesture phases
        case began
        case changed
        case ended
        case momentum  // the trackpad's inertia after the fingers left
    }

    var deltaX: CGFloat    // NSEvent.scrollingDeltaX
    var deltaY: CGFloat    // NSEvent.scrollingDeltaY
    var precise: Bool      // NSEvent.hasPreciseScrollingDeltas (trackpad, Magic Mouse)
    var inverted: Bool     // NSEvent.isDirectionInvertedFromDevice ("natural" scrolling)
    var phase: Phase
}

enum NotchScrollAction: Equatable {
    case nextTrack
    case previousTrack
    case volume(Int)  // percentage points to add
}

// Over the notch: a two-finger swipe right / left skips to the next / previous track (once per swipe), and
// scrolling up / down changes the volume. The first movement locks the axis for the rest of the gesture.
struct NotchScrollGesture {
    static let skipDistance: CGFloat = 60      // horizontal points before a swipe skips
    static let pointsPerPercent: CGFloat = 6   // vertical points per volume percentage point
    static let wheelPercent = 5                // per mouse wheel notch
    private static let axisLockDistance: CGFloat = 4

    private enum Axis { case horizontal, vertical }

    private var axis: Axis?
    private var accumulated: CGFloat = 0
    private var skipped = false

    mutating func handle(_ sample: ScrollSample) -> NotchScrollAction? {
        // Deltas follow the content; turn them into finger movement whatever "natural" scrolling says.
        let fingersRight = sample.inverted ? sample.deltaX : -sample.deltaX
        let fingersUp = sample.inverted ? -sample.deltaY : sample.deltaY

        if !sample.precise {
            guard fingersUp != 0 else { return nil }
            return .volume(fingersUp > 0 ? Self.wheelPercent : -Self.wheelPercent)
        }
        switch sample.phase {
        case .momentum, .ended:
            return nil
        case .began:
            axis = nil
            accumulated = 0
            skipped = false
        case .changed, .none:
            break
        }

        if axis == nil {
            guard max(abs(fingersRight), abs(fingersUp)) >= Self.axisLockDistance else { return nil }
            axis = abs(fingersRight) > abs(fingersUp) ? .horizontal : .vertical
        }

        switch axis {
        case .horizontal:
            accumulated += fingersRight
            guard !skipped, abs(accumulated) >= Self.skipDistance else { return nil }
            skipped = true
            return accumulated > 0 ? .nextTrack : .previousTrack
        case .vertical:
            accumulated += fingersUp
            let percent = Int(accumulated / Self.pointsPerPercent)
            guard percent != 0 else { return nil }
            accumulated -= CGFloat(percent) * Self.pointsPerPercent
            return .volume(percent)
        case nil:
            return nil
        }
    }
}

// Options › Notch Gestures.
struct NotchGesturePreferences: Equatable {
    var swipeToSkip = true
    var scrollForVolume = true
    var reverseSwipe = false
    var reverseScroll = false
}

extension NotchScrollAction {
    // nil when that gesture is turned off.
    func applying(_ preferences: NotchGesturePreferences) -> NotchScrollAction? {
        switch self {
        case .nextTrack:
            guard preferences.swipeToSkip else { return nil }
            return preferences.reverseSwipe ? .previousTrack : .nextTrack
        case .previousTrack:
            guard preferences.swipeToSkip else { return nil }
            return preferences.reverseSwipe ? .nextTrack : .previousTrack
        case .volume(let change):
            guard preferences.scrollForVolume else { return nil }
            return .volume(preferences.reverseScroll ? -change : change)
        }
    }
}

// Scrolling the volume taps the trackpad at every ten percent, like a notched wheel.
enum VolumeDetent {
    static func crossed(from old: Int, to new: Int) -> Bool {
        guard old != new else { return false }
        return old / 10 != new / 10 || new == 0 || new == 100
    }
}
