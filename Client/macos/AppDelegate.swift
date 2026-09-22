import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = HeadphonesModel()
    private let settings = AppSettings()
    private let music = MusicController()
    private let deviceWatcher = DeviceWatcher()
    private let updates = UpdateChecker()
    private var statusItemController: StatusItemController?
    private var notchController: NotchController?
    private var setupWindow: SetupWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.settings = settings
        // The notch is always built but only shows itself when the settings say so: on its own it
        // touches neither Bluetooth nor the music players.
        notchController = NotchController(model: model, music: music, settings: settings)
        setupWindow = SetupWindowController(model: model, settings: settings,
                                            onPlayerGranted: { [weak self] in self?.music.refresh() },
                                            onFinished: { [weak self] in self?.startApp() })
        if settings.setupDone {
            startApp()
        } else {
            // Nothing else starts: no menu bar icon, no Bluetooth, no update check, until the
            // setup is finished. The final button calls startApp().
            setupWindow?.show()
        }
    }

    private var appStarted = false

    private func startApp() {
        guard !appStarted else { return }
        appStarted = true

        statusItemController = StatusItemController(model: model, settings: settings, updates: updates)
        statusItemController?.onOpenSetup = { [weak self] in self?.setupWindow?.show() }

        // The music players are only read while the notch is on and used. Both publishers emit their current value first.
        settings.$showNotch.combineLatest(settings.$usageMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show, mode in
                if show && mode.usesNotch { self?.music.start() } else { self?.music.stop() }
            }
            .store(in: &cancellables)

        settings.$otherPlayers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.music.setOtherPlayers(on) }
            .store(in: &cancellables)

        deviceWatcher.onConnect = { [weak self] address, name in
            guard self?.settings.usageMode.usesHeadphones == true else { return }
            self?.model.headsetConnectedToMac(address: address, name: name)
        }
        deviceWatcher.onDisconnect = { [weak self] address in
            self?.model.headsetDisconnectedFromMac(address: address)
        }
        // In notch-only mode Bluetooth is never touched (so macOS never asks for it). Switching to a mode with
        // the headphones starts it; leaving it drops the link.
        settings.$usageMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in self?.applyHeadphones(mode.usesHeadphones) }
            .store(in: &cancellables)

        updates.start()
    }

    private var headphonesStarted = false

    private func applyHeadphones(_ used: Bool) {
        if used {
            guard !headphonesStarted else { return }
            headphonesStarted = true
            deviceWatcher.start()
            if settings.autoConnect { model.autoConnectOnLaunch() }
        } else if model.connectionState != .disconnected {
            model.disconnect()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.disconnect()
    }
}
