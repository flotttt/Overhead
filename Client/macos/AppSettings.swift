import Foundation
import ServiceManagement

// The user options, persisted in UserDefaults. Launch at login is backed by SMAppService (macOS 13+).
final class AppSettings: ObservableObject {
    private enum Keys {
        static let autoConnect = "autoConnect"
        static let autoReconnect = "autoReconnect"
        static let lastDeviceAddress = "lastDeviceAddress"
        static let showNotch = "showNotch"
    }

    private let defaults: UserDefaults

    @Published var autoConnect: Bool {
        didSet { defaults.set(autoConnect, forKey: Keys.autoConnect) }
    }
    @Published var autoReconnect: Bool {
        didSet { defaults.set(autoReconnect, forKey: Keys.autoReconnect) }
    }
    @Published var showNotch: Bool {
        didSet { defaults.set(showNotch, forKey: Keys.showNotch) }
    }
    @Published private(set) var launchAtLogin: Bool

    var lastDeviceAddress: String? {
        get { defaults.string(forKey: Keys.lastDeviceAddress) }
        set { defaults.set(newValue, forKey: Keys.lastDeviceAddress) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Spec §4: auto-connect and auto-reconnect default on; launch at login stays off until the user asks.
        // Notch spec §7: the notch is shown by default.
        defaults.register(defaults: [Keys.autoConnect: true, Keys.autoReconnect: true, Keys.showNotch: true])
        autoConnect = defaults.bool(forKey: Keys.autoConnect)
        autoReconnect = defaults.bool(forKey: Keys.autoReconnect)
        showNotch = defaults.bool(forKey: Keys.showNotch)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // Returns an error message if macOS refused the change.
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        defer { launchAtLogin = SMAppService.mainApp.status == .enabled }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
