import Foundation
import ServiceManagement

// The user options, persisted in UserDefaults. Launch at login is backed by SMAppService (macOS 13+).
final class AppSettings: ObservableObject {
    private enum Keys {
        static let autoConnect = "autoConnect"
        static let autoReconnect = "autoReconnect"
        static let lastDeviceAddress = "lastDeviceAddress"
        static let showNotch = "showNotch"
        static let notchWidth = "notchOpenWidth"
        static let notchHeight = "notchOpenHeight"
        static let notchSide = "notchSideWidth"
        static let notchZoom = "notchZoom"
        static let notchArtwork = "notchRestingArtwork"
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

    // Notch Size submenu. Stored as the user set them; NotchLayout clamps.
    @Published var notchWidth: Double { didSet { defaults.set(notchWidth, forKey: Keys.notchWidth) } }
    @Published var notchHeight: Double { didSet { defaults.set(notchHeight, forKey: Keys.notchHeight) } }
    @Published var notchSideWidth: Double { didSet { defaults.set(notchSideWidth, forKey: Keys.notchSide) } }
    @Published var notchZoom: Double { didSet { defaults.set(notchZoom, forKey: Keys.notchZoom) } }
    @Published var notchArtwork: Double { didSet { defaults.set(notchArtwork, forKey: Keys.notchArtwork) } }
    // True while the Notch Size submenu is open: the notch stays open as a live preview. Not persisted.
    @Published var notchPreviewing = false

    var notchLayout: NotchLayout {
        NotchLayout(openSize: CGSize(width: notchWidth, height: notchHeight),
                    sideExtension: CGFloat(notchSideWidth), zoom: CGFloat(notchZoom),
                    restingArtwork: CGFloat(notchArtwork))
    }

    var lastDeviceAddress: String? {
        get { defaults.string(forKey: Keys.lastDeviceAddress) }
        set { defaults.set(newValue, forKey: Keys.lastDeviceAddress) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.importSandboxedSettings(into: defaults)
        // Spec §4: auto-connect and auto-reconnect default on; launch at login stays off until the user asks.
        // Notch spec §7: the notch is shown by default.
        let layout = NotchLayout.default
        defaults.register(defaults: [
            Keys.autoConnect: true, Keys.autoReconnect: true, Keys.showNotch: true,
            Keys.notchWidth: Double(layout.openSize.width), Keys.notchHeight: Double(layout.openSize.height),
            Keys.notchSide: Double(layout.sideExtension), Keys.notchZoom: Double(layout.zoom),
            Keys.notchArtwork: Double(layout.restingArtwork),
        ])
        autoConnect = defaults.bool(forKey: Keys.autoConnect)
        autoReconnect = defaults.bool(forKey: Keys.autoReconnect)
        showNotch = defaults.bool(forKey: Keys.showNotch)
        notchWidth = defaults.double(forKey: Keys.notchWidth)
        notchHeight = defaults.double(forKey: Keys.notchHeight)
        notchSideWidth = defaults.double(forKey: Keys.notchSide)
        notchZoom = defaults.double(forKey: Keys.notchZoom)
        notchArtwork = defaults.double(forKey: Keys.notchArtwork)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // Up to 1.1.0 the app was sandboxed and kept its settings in its container. The first unsandboxed launch
    // copies them over, without overwriting anything already set.
    private static func importSandboxedSettings(into defaults: UserDefaults) {
        let doneKey = "importedSandboxedSettings"
        guard !defaults.bool(forKey: doneKey), let bundleID = Bundle.main.bundleIdentifier else { return }
        defaults.set(true, forKey: doneKey)
        let container = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist")
        guard let old = NSDictionary(contentsOf: container) as? [String: Any] else { return }
        let keys = [Keys.autoConnect, Keys.autoReconnect, Keys.lastDeviceAddress, Keys.showNotch, Keys.notchWidth,
                    Keys.notchHeight, Keys.notchSide, Keys.notchZoom, Keys.notchArtwork]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = old[key] { defaults.set(value, forKey: key) }
        }
    }

    func resetNotchSize() {
        let layout = NotchLayout.default
        notchWidth = Double(layout.openSize.width)
        notchHeight = Double(layout.openSize.height)
        notchSideWidth = Double(layout.sideExtension)
        notchZoom = Double(layout.zoom)
        notchArtwork = Double(layout.restingArtwork)
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
