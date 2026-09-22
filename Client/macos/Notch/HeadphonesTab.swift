import AppKit
import SwiftUI

// Notch headphones page: NC / Ambient / Off, ambient level and Focus on Voice. It calls the same
// model methods as the menu, so the poll guard and the send throttle apply here too, and both stay in sync.
struct HeadphonesTab: View {
    @ObservedObject var model: HeadphonesModel
    let back: () -> Void
    let openSettings: () -> Void
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            HStack(spacing: 6 * s) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 24 * s, height: 24 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(tr("Back"))
                Image(systemName: "headphones").font(.system(size: 13 * s)).foregroundColor(.white)
                Text(model.deviceName.isEmpty ? tr("Headphones") : model.deviceName)
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 24 * s, height: 24 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(tr("Quick Settings…"))
            }
            switch model.connectionState {
            case .connected:
                controls
            case .connecting:
                Text(tr("Connecting…"))
                    .font(.system(size: 12 * s))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8 * s)
            case .disconnected:
                HStack(spacing: 10 * s) {
                    Text(tr("Not connected")).font(.system(size: 12 * s)).foregroundColor(.gray)
                    NotchPillButton(title: tr("Connect…")) {
                        NSApp.activate(ignoringOtherApps: true)  // the fallback Bluetooth picker is a modal window
                        model.connect()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8 * s)
            }
        }
    }

    private var controls: some View {
        let ambient = model.mode == .ambientSound
        return VStack(spacing: 10 * s) {
            ModePicker(selection: model.mode, select: { model.setMode($0) })

            HStack(spacing: 8 * s) {
                Text(tr("Level")).font(.system(size: 12 * s)).foregroundColor(.gray)
                FlatSlider(value: Double(model.ambientLevel), range: 1...Double(max(model.maxAmbientLevel, 2)),
                           step: 1) { value, final in
                    model.setLevel(Int(value.rounded()), final: final)
                }
                Text(verbatim: "\(model.ambientLevel)")
                    .font(.system(size: 11 * s, weight: .medium).monospacedDigit())
                    .foregroundColor(.gray)
                    .frame(width: 20 * s, alignment: .trailing)
                Text(tr("Voice")).font(.system(size: 12 * s)).foregroundColor(.gray).padding(.leading, 6 * s)
                NotchSwitch(isOn: model.focusOnVoice, label: tr("Focus on Voice")) { model.setFocusOnVoice($0) }
            }
            .disabled(!ambient)
            .opacity(ambient ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.2), value: ambient)
        }
    }
}

// Segmented NC / Ambient / Off control drawn in SwiftUI. The AppKit segmented picker insists on its natural
// width, wider than the notch in French, and only shrank on the next model update (~2 s later). Short labels:
// the full ones ("Réduction de bruit") don't fit a third of the notch.
private struct ModePicker: View {
    let selection: SHCAmbientMode
    let select: (SHCAmbientMode) -> Void
    @Environment(\.notchScale) private var s
    @Namespace private var pill

    private static var options: [(SHCAmbientMode, String)] {
        [(.noiseCanceling, tr("NC")), (.ambientSound, tr("Ambient")), (.off, tr("Off"))]
    }

    var body: some View {
        HStack(spacing: 2 * s) {
            ForEach(Self.options, id: \.0.rawValue) { mode, title in
                let selected = selection == mode
                Button { select(mode) } label: {
                    Text(title)
                        .font(.system(size: 11 * s, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected ? .white : .gray)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5 * s)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6 * s)
                                    .fill(Color(white: 0.3))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2 * s)
        .background(RoundedRectangle(cornerRadius: 8 * s).fill(Color(white: 0.15)))
        // The selection comes back from the headset (menu, NC button), so animate on the value, not the click.
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}
