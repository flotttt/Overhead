import SwiftUI

// One Notch Size slider ("Open Width        ━━━●━━  300"), bound to an AppSettings value.
struct NotchSizeRow: View {
    @ObservedObject var settings: AppSettings
    let title: String
    let keyPath: ReferenceWritableKeyPath<AppSettings, Double>
    let range: ClosedRange<CGFloat>
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
            Slider(value: Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
                .controlSize(.small)
            Text(verbatim: format(settings[keyPath: keyPath]))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.leading, MenuMetrics.leading)
        .padding(.trailing, MenuMetrics.trailing)
        .padding(.vertical, 3)
    }
}
