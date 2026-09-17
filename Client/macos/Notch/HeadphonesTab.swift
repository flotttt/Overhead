import AppKit
import SwiftUI

// Notch tab: NC / Ambient / Off, ambient level and Focus on Voice (spec §4.2). It calls the same model methods
// as the menu, so the poll guard and the send throttle apply here too, and both stay in sync.
struct HeadphonesTab: View {
    @ObservedObject var model: HeadphonesModel

    var body: some View {
        switch model.connectionState {
        case .connected:
            controls
        case .connecting:
            Text(tr("Connecting…")).font(.system(size: 12)).foregroundColor(.gray).padding(.top, 16)
        case .disconnected:
            VStack(spacing: 10) {
                Text(tr("Not connected")).font(.system(size: 12)).foregroundColor(.gray)
                Button(tr("Connect…")) {
                    NSApp.activate(ignoringOtherApps: true)  // the fallback Bluetooth picker is a modal window
                    model.connect()
                }
                .controlSize(.small)
            }
            .padding(.top, 16)
        }
    }

    private var controls: some View {
        let ambient = model.mode == .ambientSound
        return VStack(spacing: 12) {
            ModePicker(selection: model.mode, select: { model.setMode($0) })

            HStack(spacing: 8) {
                Text(tr("Level")).font(.system(size: 12))
                Slider(
                    value: Binding(get: { Double(model.ambientLevel) },
                                   set: { model.setLevel(Int($0.rounded()), final: false) }),
                    in: 1...Double(max(model.maxAmbientLevel, 2)),
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing { model.setLevel(model.ambientLevel, final: true) }
                    }
                )
                .controlSize(.small)
                Text(verbatim: "\(model.ambientLevel)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.gray)
                    .frame(width: 20, alignment: .trailing)
            }
            .disabled(!ambient)
            .opacity(ambient ? 1 : 0.4)

            HStack {
                Text(tr("Focus on Voice")).font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(get: { model.focusOnVoice }, set: { model.setFocusOnVoice($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .disabled(!ambient)
            .opacity(ambient ? 1 : 0.4)
        }
    }
}

// Segmented NC / Ambient / Off control drawn in SwiftUI. The AppKit segmented picker insists on its natural
// width, wider than the notch in French, and only shrank on the next model update (~2 s later).
private struct ModePicker: View {
    let selection: SHCAmbientMode
    let select: (SHCAmbientMode) -> Void

    private static var options: [(SHCAmbientMode, String)] {
        [(.noiseCanceling, tr("Noise Canceling")), (.ambientSound, tr("Ambient Sound")), (.off, tr("Off"))]
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.options, id: \.0.rawValue) { mode, title in
                let selected = selection == mode
                Button { select(mode) } label: {
                    Text(title)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected ? .white : .gray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color(white: 0.3) : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15)))
    }
}
