import SwiftUI

// Options › Notch Gestures: "Strength  ━━●━━  Medium", tapping the trackpad at each step while it moves.
struct HapticStrengthRow: View {
    @ObservedObject var settings: AppSettings

    private var label: String {
        switch settings.hapticStrength {
        case ...1: return tr("Light")
        case 2: return tr("Medium")
        default: return tr("Strong")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(tr("Strength"))
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)
            Slider(value: Binding(get: { Double(settings.hapticStrength) },
                                  set: { settings.hapticStrength = Int($0.rounded()) }),
                   in: Double(NotchHaptics.strengthRange.lowerBound)...Double(NotchHaptics.strengthRange.upperBound),
                   step: 1)
                .controlSize(.small)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.leading, MenuMetrics.leading)
        .padding(.trailing, MenuMetrics.trailing)
        .padding(.vertical, 3)
        .disabled(!settings.anyHaptics)
        .onChange(of: settings.hapticStrength) { strength in NotchHaptics.preview(strength: strength) }
    }
}
