import AppKit

// Light taps on the Force Touch trackpad: notch opening, button presses, track skips, volume detents. Only felt
// while a finger rests on the trackpad. Options › Notch Gestures turns each kind on or off, and the strength
// slider picks one of three levels (macOS only offers three patterns; "strong" doubles its tap).
enum NotchHaptics {
    enum Event {
        case notchOpens
        case buttonPress
        case trackSkip
        case volumeDetent
    }

    static let strengthRange = 1...3

    static var enabledEvents: Set<Event> = [.notchOpens, .buttonPress, .trackSkip, .volumeDetent]
    static var strength = 2

    static func tap(_ event: Event) {
        guard enabledEvents.contains(event) else { return }
        perform(strength: strength)
    }

    // A tap at a given strength, felt while moving the strength slider.
    static func preview(strength: Int) {
        perform(strength: strength)
    }

    private static func perform(strength: Int) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch strength {
        case ...1:
            performer.perform(.generic, performanceTime: .now)
        case 2:
            performer.perform(.alignment, performanceTime: .now)
        default:
            performer.perform(.levelChange, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        }
    }
}
