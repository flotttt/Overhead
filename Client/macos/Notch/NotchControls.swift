import SwiftUI

// Controls drawn in SwiftUI for the notch. The AppKit-backed ones (Toggle .switch, bordered Button, segmented
// Picker) are separate views that ignore SwiftUI's scale and clip: while the notch closed, they stayed full
// size past the shrinking shape.

// A small on/off switch.
struct NotchSwitch: View {
    let isOn: Bool
    let label: String
    let set: (Bool) -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { set(!isOn) } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Color.green : Color(white: 0.3))
                Circle().fill(Color.white).padding(2)
            }
            .frame(width: 30, height: 18)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? Text(verbatim: "1") : Text(verbatim: "0"))
        .accessibilityAddTraits(.isButton)
    }
}

// A rounded grey text button ("Connect…", "Open Spotify").
struct NotchPillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(white: 0.22)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
