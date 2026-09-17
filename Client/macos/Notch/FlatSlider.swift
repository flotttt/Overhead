import SwiftUI

// A thick flat bar without a knob (progress, volume, level). Click or drag anywhere on it; `onChange` gets the
// value while dragging (final: false) and once more when the pointer is released (final: true). `smoothing`
// glides the fill between values that arrive once a second (playback progress).
struct FlatSlider: View {
    let value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double?
    var height: CGFloat = 5
    var smoothing = false
    let onChange: (Double, Bool) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var dragging = false
    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? min(1, max(0, (value - range.lowerBound) / span)) : 0
            let barHeight = dragging || hovering ? height + 2 : height
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.25))
                Capsule()
                    .fill(Color(white: dragging || hovering ? 1 : 0.75))
                    .frame(width: max(barHeight, width * fraction))
                    .opacity(fraction > 0 ? 1 : 0)
                    .animation(smoothing && !dragging ? .linear(duration: 1) : .easeOut(duration: 0.08), value: fraction)
            }
            .frame(height: barHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        onChange(Self.value(at: drag.location.x / width, range: range, step: step), false)
                    }
                    .onEnded { drag in
                        dragging = false
                        onChange(Self.value(at: drag.location.x / width, range: range, step: step), true)
                    }
            )
            .onHover { hovering = isEnabled && $0 }
            .animation(.easeOut(duration: 0.12), value: barHeight)
        }
        .frame(height: height + 8)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private static func value(at fraction: CGFloat, range: ClosedRange<Double>, step: Double?) -> Double {
        let raw = range.lowerBound + Double(min(1, max(0, fraction))) * (range.upperBound - range.lowerBound)
        guard let step = step, step > 0 else { return raw }
        return (raw / step).rounded() * step
    }
}
