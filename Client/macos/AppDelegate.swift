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
        statusItemController = StatusItemController(model: model, settings: settings, updates: updates)
        notchController = NotchController(model: model, music: music, settings: settings)
        setupWindow = SetupWindowController(model: model, settings: settings,
                                            onSpotifyGranted: { [weak self] in self?.music.refresh() })
        statusItemController?.onOpenSetup = { [weak self] in self?.setupWindow?.show() }
        if !settings.setupDone { setupWindow?.show() }

        // Spotify is only read while the notch is on. $showNotch emits the current value first.
        settings.$showNotch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                if show { self?.music.start() } else { self?.music.stop() }
            }
            .store(in: &cancellables)

        deviceWatcher.onConnect = { [weak self] address, name in
            self?.model.headsetConnectedToMac(address: address, name: name)
        }
        deviceWatcher.onDisconnect = { [weak self] address in
            self?.model.headsetDisconnectedFromMac(address: address)
        }
        deviceWatcher.start()

        if settings.autoConnect { model.autoConnectOnLaunch() }
        updates.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.disconnect()
    }
}
