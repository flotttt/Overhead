import AppKit
import Combine
import CoreBluetooth

// One music app as the setup assistant shows it.
struct PlayerCheck: Equatable {
    var running = false
    var access = SetupAccess.unavailable
    var asking = false  // macOS's prompt is up, waiting for an answer
}

// What the setup assistant checks, refreshed every second while its window is open: Bluetooth access, and for
// each music app whether it's running and whether Overhead may control it.
final class SetupChecks: ObservableObject {
    @Published private(set) var bluetooth = SetupAccess.unavailable
    @Published private(set) var players: [String: PlayerCheck] = [:]  // by ScriptedPlayer.id

    // Called once control of a music app is granted, so the notch reads it right away.
    var onPlayerGranted: (() -> Void)?

    private var timer: Timer?
    private var bluetoothRequest: CBCentralManager?
    // AEDeterminePermissionToAutomateTarget can block (it waits for the user when it asks): never on main.
    // Serial, so macOS's questions come one after the other.
    private let queue = DispatchQueue(label: "com.overhead.setup")

    func check(_ player: ScriptedPlayer) -> PlayerCheck { players[player.id] ?? PlayerCheck() }

    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let bluetoothAccess = SetupAccess.bluetooth(rawAuthorization: CBCentralManager.authorization.rawValue)
        if bluetoothAccess != bluetooth { fputs("[setup] Bluetooth: \(bluetoothAccess)\n", stderr) }
        bluetooth = bluetoothAccess
        ScriptedPlayer.all.forEach(refresh)
    }

    private func refresh(_ player: ScriptedPlayer) {
        let running = Self.isRunning(player)
        players[player.id, default: PlayerCheck()].running = running
        guard running else {
            players[player.id]?.access = .unavailable
            return
        }
        guard !check(player).asking else { return }
        queue.async { [weak self] in
            let status = Self.permission(for: player, ask: false)
            DispatchQueue.main.async {
                guard let self = self, !self.check(player).asking else { return }
                let access = SetupAccess.automation(status: status)
                if access != self.check(player).access {
                    fputs("[setup] \(player.id) control: \(access) (\(status))\n", stderr)
                }
                self.players[player.id]?.access = access
            }
        }
    }

    // Creating a Bluetooth manager is what makes macOS ask.
    func requestBluetooth() {
        NSApp.activate(ignoringOtherApps: true)
        bluetoothRequest = CBCentralManager(delegate: nil, queue: nil)
    }

    // Shows macOS's prompt (in front: the app is activated first) and waits for the answer off the main thread.
    func request(_ player: ScriptedPlayer) {
        guard check(player).running, !check(player).asking else { return }
        players[player.id]?.asking = true
        NSApp.activate(ignoringOtherApps: true)
        queue.async { [weak self] in
            let status = Self.permission(for: player, ask: true)
            DispatchQueue.main.async {
                guard let self = self else { return }
                let access = SetupAccess.automation(status: status)
                self.players[player.id]?.asking = false
                self.players[player.id]?.access = access
                if access == .granted { self.onPlayerGranted?() }
            }
        }
    }

    // macOS never asks again about a refused permission: forget Overhead's answers, then ask. tccutil can reset
    // an app's own entry without administrator rights, but only all its Apple Events answers at once: the other
    // music apps that were allowed and are open get asked again too (a closed one asks when the notch next reads it).
    func askAgain(_ player: ScriptedPlayer) {
        guard check(player).running, !check(player).asking, let bundleID = Bundle.main.bundleIdentifier else { return }
        let alsoAllowed = ScriptedPlayer.all.filter {
            $0.id != player.id && check($0).running && check($0).access == .granted
        }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "AppleEvents", bundleID]
        reset.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                for asked in [player] + alsoAllowed {
                    self.players[asked.id]?.access = .notDetermined
                    self.request(asked)
                }
            }
        }
        do {
            try reset.run()
        } catch {
            openAutomationSettings()
        }
    }

    func launch(_ player: ScriptedPlayer) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) else {
            if let download = player.downloadURL { NSWorkspace.shared.open(download) }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    func openAutomationSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    func openBluetoothSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
    }

    private func openSettings(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    private static func isRunning(_ player: ScriptedPlayer) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }

    private static func permission(for player: ScriptedPlayer, ask: Bool) -> Int {
        let target = NSAppleEventDescriptor(bundleIdentifier: player.bundleIdentifier)
        return Int(AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard),
                                                         AEEventID(typeWildCard), ask))
    }
}
