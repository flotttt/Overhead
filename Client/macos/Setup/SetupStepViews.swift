import SwiftUI

// The setup steps. Each one is a plain view over the same AppSettings and SetupChecks; SetupView
// decides which one is on screen and how the user moves between them.

// Step 1: how Overhead is going to be used. Changing it changes the steps that follow.
struct ModeStepView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("How do you want to use Overhead?")).font(.headline)
            HStack(spacing: 10) {
                ModeCard(mode: .notchOnly, icon: "music.note", title: tr("Notch"),
                         detail: tr("Your music in the notch, no headphones needed."), selection: $settings.usageMode)
                ModeCard(mode: .headphonesOnly, icon: "headphones", title: tr("Headphones"),
                         detail: tr("Your Sony headphones' settings in the menu bar."), selection: $settings.usageMode)
                ModeCard(mode: .both, icon: "sparkles", title: tr("Both"),
                         detail: tr("The notch and the headphones together."), selection: $settings.usageMode)
            }
        }
    }
}

// Step 2: what macOS has to allow, for the chosen mode only.
struct PermissionsStepView: View {
    @ObservedObject var checks: SetupChecks
    @ObservedObject var model: HeadphonesModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            if settings.usageMode.usesHeadphones {
                bluetoothRow
                Divider()
                headphonesRow
                if settings.usageMode.usesNotch { Divider() }
            }
            // Each music app is optional: the notch works with whichever the user plays.
            if settings.usageMode.usesNotch {
                ForEach(Array(ScriptedPlayer.all.enumerated()), id: \.element.id) { index, player in
                    playerRow(player)
                    if index < ScriptedPlayer.all.count - 1 { Divider() }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
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

// Last step: the one setting that has nothing to do with a permission, and the way out.
struct DoneStepView: View {
    @ObservedObject var settings: AppSettings
    let showError: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("You're all set.")).font(.headline)
            VStack(spacing: 0) {
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
            Text(tr("You can open this window again with Setup… in the Overhead menu."))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
