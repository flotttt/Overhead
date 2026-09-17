import AppKit
import SwiftUI

// Shared motion for the notch: springs, how content follows the shape, and button press feedback.
// With "Reduce motion" on, springs become short eases and nothing scales or moves.
enum NotchMotion {
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static var open: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.74) }
    static var close: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 1) }
    static var content: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85) }

    static let morphScale: CGFloat = 0.6

    // The open panel's content grows out of the notch with the shape (same spring, no delay), instead of
    // popping in after it: video at 60 fps showed a blurred panel appearing ~6 frames late. Closing is driven
    // by NotchView (FadeScale on isOpen), and the content is unmounted once the shape has shrunk.
    static var morph: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FadeScale(amount: 1, scale: morphScale), identity: FadeScale(amount: 0, scale: morphScale)),
            removal: .identity)
    }

    // The resting icons leave at once when the shape grows, and come back once it has shrunk.
    static func resting(open: Bool) -> Animation {
        open ? .easeOut(duration: 0.06) : .easeOut(duration: 0.2).delay(reduceMotion ? 0 : 0.12)
    }
}

// amount 0 = shown; 1 = transparent and scaled down to `scale` (anchored at the top, towards the notch).
// Opacity and transforms only: cheap to animate at 120 Hz, unlike blur.
struct FadeScale: ViewModifier {
    let amount: CGFloat
    var scale: CGFloat = 0.94

    func body(content: Content) -> some View {
        let motion = !NotchMotion.reduceMotion
        return content
            .opacity(Double(1 - amount))
            .scaleEffect(motion ? 1 - (1 - scale) * amount : 1, anchor: .top)
    }
}

// Buttons shrink a little while pressed, and spring back.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !NotchMotion.reduceMotion ? 0.84 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Text and icon zoom inside the notch (Options › Notch Size › Text Size, already limited to what fits).
private struct NotchScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var notchScale: CGFloat {
        get { self[NotchScaleKey.self] }
        set { self[NotchScaleKey.self] = newValue }
    }
}

extension View {
    // SF Symbol swaps (play ↔ pause) morph on macOS 14+; older systems cross-fade.
    @ViewBuilder func symbolReplaceTransition() -> some View {
        if #available(macOS 14.0, *) {
            contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }
}
