import AppKit
import Combine
import CoreBluetooth

// What the setup assistant checks, refreshed every second while its window is open: Bluetooth access, whether
// Spotify is running, and whether SonyNotch may control it.
final class SetupChecks: ObservableObject {
    private static let spotifyID = "com.spotify.client"

    @Published private(set) var bluetooth = SetupAccess.unavailable
    @Published private(set) var spotifyRunning = false
    @Published private(set) var spotify = SetupAccess.unavailable
    @Published private(set) var askingSpotify = false  // macOS's prompt is up, waiting for an answer

    // Called once Spotify control is granted, so the notch reads Spotify right away.
    var onSpotifyGranted: (() -> Void)?

    private var timer: Timer?
    private var bluetoothRequest: CBCentralManager?
    // AEDeterminePermissionToAutomateTarget can block (it waits for the user when it asks): never on main.
    private let queue = DispatchQueue(label: "com.sonynotch.setup")

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
        spotifyRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyID).isEmpty
        guard spotifyRunning else {
            spotify = .unavailable
            return
        }
        guard !askingSpotify else { return }
        queue.async { [weak self] in
            let status = Self.spotifyPermission(ask: false)
            DispatchQueue.main.async {
                guard let self = self, !self.askingSpotify else { return }
                let access = SetupAccess.spotify(status: status)
                if access != self.spotify { fputs("[setup] Spotify control: \(access) (\(status))\n", stderr) }
                self.spotify = access
            }
        }
    }

    // Creating a Bluetooth manager is what makes macOS ask.
    func requestBluetooth() {
        NSApp.activate(ignoringOtherApps: true)
        bluetoothRequest = CBCentralManager(delegate: nil, queue: nil)
    }

    // Shows macOS's prompt (in front: the app is activated first) and waits for the answer off the main thread.
    func requestSpotify() {
        guard spotifyRunning, !askingSpotify else { return }
        askingSpotify = true
        NSApp.activate(ignoringOtherApps: true)
        queue.async { [weak self] in
            let status = Self.spotifyPermission(ask: true)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.askingSpotify = false
                self.spotify = SetupAccess.spotify(status: status)
                if self.spotify == .granted { self.onSpotifyGranted?() }
            }
        }
    }

    // macOS never asks again about a refused permission: forget SonyNotch's answer about Spotify (and only that),
    // then ask. tccutil can reset an app's own entry without administrator rights.
    func askSpotifyAgain() {
        guard spotifyRunning, !askingSpotify, let bundleID = Bundle.main.bundleIdentifier else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "AppleEvents", bundleID]
        reset.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.spotify = .notDetermined
                self?.requestSpotify()
            }
        }
        do {
            try reset.run()
        } catch {
            openAutomationSettings()
        }
    }

    func launchSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyID) else {
            NSWorkspace.shared.open(URL(string: "https://www.spotify.com/download/mac/")!)
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

    private static func spotifyPermission(ask: Bool) -> Int {
        let target = NSAppleEventDescriptor(bundleIdentifier: spotifyID)
        return Int(AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard),
                                                         AEEventID(typeWildCard), ask))
    }
}
