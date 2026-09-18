import SwiftUI

// The setup assistant: one row per thing SonyNotch needs, each turning green once it's done, with the button
// that fixes it (or, once it's fine, reopens or redoes it: nothing is ever stuck). Shown at first launch, and from
// "Setup…" in the menu.
struct SetupView: View {
    @ObservedObject var checks: SetupChecks
    @ObservedObject var model: HeadphonesModel
    @ObservedObject var settings: AppSettings
    let showError: (String) -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Welcome to SonyNotch")).font(.title2.weight(.semibold))
                    Text(tr("A few permissions and your headphones, and you're set.")).foregroundColor(.secondary)
                }
            }

            Text(tr("How do you want to use SonyNotch?")).font(.headline)
            HStack(spacing: 10) {
                ModeCard(mode: .notchOnly, icon: "music.note", title: tr("Notch"),
                         detail: tr("Spotify in the notch, no headphones needed."), selection: $settings.usageMode)
                ModeCard(mode: .headphonesOnly, icon: "headphones", title: tr("Headphones"),
                         detail: tr("Your Sony headphones' settings in the menu bar."), selection: $settings.usageMode)
                ModeCard(mode: .both, icon: "sparkles", title: tr("Both"),
                         detail: tr("The notch and the headphones together."), selection: $settings.usageMode)
            }

            VStack(spacing: 0) {
                if settings.usageMode.usesHeadphones {
                    bluetoothRow
                    Divider()
                    headphonesRow
                    Divider()
                }
                if settings.usageMode.usesNotch {
                    spotifyRow
                    Divider()
                }
                SetupRow(icon: "power", title: tr("Launch at Login"),
                         detail: tr("Start SonyNotch when you log in to your Mac."),
                         done: settings.launchAtLogin) {
                    Toggle("", isOn: Binding(get: { settings.launchAtLogin }, set: { on in
                        if let error = settings.setLaunchAtLogin(on) { showError(error) }
                    }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))

            HStack {
                Text(tr("You can open this window again with Setup… in the SonyNotch menu."))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Button(tr("Done"), action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .animation(.easeInOut(duration: 0.2), value: settings.usageMode)
    }

    private var bluetoothRow: some View {
        SetupRow(icon: "antenna.radiowaves.left.and.right", title: tr("Bluetooth"),
                 detail: bluetoothDetail, done: checks.bluetooth == .granted) {
            // Always something to click: macOS only asks once, afterwards the switch is in System Settings.
            if checks.bluetooth == .notDetermined {
                Button(tr("Allow")) { checks.requestBluetooth() }
            } else {
                Button(tr("Settings")) { checks.openBluetoothSettings() }
            }
        }
    }

    private var bluetoothDetail: String {
        switch checks.bluetooth {
        case .granted: return tr("SonyNotch can talk to your headphones.")
        case .denied: return tr("Bluetooth access was refused. Turn SonyNotch on in Privacy & Security › Bluetooth.")
        default: return tr("Needed to talk to your headphones.")
        }
    }

    private var headphonesRow: some View {
        SetupRow(icon: "headphones", title: tr("Headphones"), detail: headphonesDetail, done: model.connected) {
            switch model.connectionState {
            case .disconnected:
                Button(tr("Connect…")) {
                    NSApp.activate(ignoringOtherApps: true)
                    model.connect()
                }
                .disabled(checks.bluetooth == .denied)
            case .connecting:
                ProgressView().controlSize(.small)
            case .connected:
                Button(tr("Reconnect")) { model.reconnect() }
            }
        }
    }

    private var headphonesDetail: String {
        switch model.connectionState {
        case .connected: return model.deviceName.isEmpty ? tr("Connected.") : model.deviceName
        case .connecting: return tr("Connecting…")
        case .disconnected: return tr("Pair your Sony headphones in System Settings › Bluetooth, then connect them here.")
        }
    }

    private var spotifyRow: some View {
        SetupRow(icon: "music.note", title: tr("Spotify"), detail: spotifyDetail,
                 done: checks.spotify == .granted, optional: settings.usageMode.usesHeadphones) {
            if !checks.spotifyRunning {
                Button(tr("Open Spotify")) { checks.launchSpotify() }
            } else if checks.askingSpotify {
                ProgressView().controlSize(.small)
            } else {
                switch checks.spotify {
                case .granted: Button(tr("Settings")) { checks.openAutomationSettings() }
                case .denied: Button(tr("Ask Again")) { checks.askSpotifyAgain() }
                default: Button(tr("Allow")) { checks.requestSpotify() }  // not asked yet, or macOS can't tell
                }
            }
        }
    }

    private var spotifyDetail: String {
        if !checks.spotifyRunning { return tr("For the notch player. Open Spotify to allow SonyNotch to control it.") }
        if checks.askingSpotify { return tr("Answer macOS's question: click Allow.") }
        switch checks.spotify {
        case .granted: return tr("SonyNotch can show and control your music.")
        case .denied: return tr("Control was refused. Ask Again shows macOS's question once more.")
        default: return tr("Allow SonyNotch to show and control the music playing in Spotify.")
        }
    }
}

// One way of using SonyNotch, picked by clicking the card.
private struct ModeCard: View {
    let mode: UsageMode
    let icon: String
    let title: String
    let detail: String
    @Binding var selection: UsageMode

    var body: some View {
        let selected = selection == mode
        Button { selection = mode } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon).font(.system(size: 18)).foregroundColor(.accentColor)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected ? .accentColor : Color(nsColor: .tertiaryLabelColor))
                }
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SetupRow<Action: View>: View {
    let icon: String
    let title: String
    let detail: String
    let done: Bool
    var optional = false
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).fontWeight(.medium)
                    if optional { Text(tr("Optional")).font(.caption).foregroundColor(.secondary) }
                }
                Text(detail).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(done ? .green : Color(nsColor: .tertiaryLabelColor))
                .accessibilityLabel(done ? tr("Done") : tr("To do"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
