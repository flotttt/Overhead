import SwiftUI

// The setup assistant: one row per thing Overhead needs, each turning green once it's done, with the button
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
                    Text(tr("Welcome to Overhead")).font(.title2.weight(.semibold))
                    Text(tr("A few permissions and your headphones, and you're set.")).foregroundColor(.secondary)
                }
            }

            Text(tr("How do you want to use Overhead?")).font(.headline)
            HStack(spacing: 10) {
                ModeCard(mode: .notchOnly, icon: "music.note", title: tr("Notch"),
                         detail: tr("Your music in the notch, no headphones needed."), selection: $settings.usageMode)
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
                // Each music app is optional: the notch works with whichever the user plays.
                if settings.usageMode.usesNotch {
                    ForEach(ScriptedPlayer.all, id: \.id) { player in
                        playerRow(player)
                        Divider()
                    }
                }
                SetupRow(icon: "power", title: tr("Launch at Login"),
                         detail: tr("Start Overhead when you log in to your Mac."),
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
                Text(tr("You can open this window again with Setup… in the Overhead menu."))
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
        case .granted: return tr("Overhead can talk to your headphones.")
        case .denied: return tr("Bluetooth access was refused. Turn Overhead on in Privacy & Security › Bluetooth.")
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

    private func playerRow(_ player: ScriptedPlayer) -> some View {
        let check = checks.check(player)
        return SetupRow(icon: "music.note", title: player.name, detail: playerDetail(player, check),
                        done: check.access == .granted, optional: true) {
            if !check.running {
                Button(String(format: tr("Open %@"), player.name)) { checks.launch(player) }
            } else if check.asking {
                ProgressView().controlSize(.small)
            } else {
                switch check.access {
                case .granted: Button(tr("Settings")) { checks.openAutomationSettings() }
                case .denied: Button(tr("Ask Again")) { checks.askAgain(player) }
                default: Button(tr("Allow")) { checks.request(player) }  // not asked yet, or macOS can't tell
                }
            }
        }
    }

    private func playerDetail(_ player: ScriptedPlayer, _ check: PlayerCheck) -> String {
        if !check.running {
            return String(format: tr("For the notch player. Open %@ to allow Overhead to control it."), player.name)
        }
        if check.asking { return tr("Answer macOS's question: click Allow.") }
        switch check.access {
        case .granted: return tr("Overhead can show and control your music.")
        case .denied: return tr("Control was refused. Ask Again shows macOS's question once more.")
        default: return String(format: tr("Allow Overhead to show and control the music playing in %@."), player.name)
        }
    }
}

// One way of using Overhead, picked by clicking the card.
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
