import Foundation
import ServiceManagement

// The user options, persisted in UserDefaults. Launch at login is backed by SMAppService (macOS 13+).
final class AppSettings: ObservableObject {
    private enum Keys {
        static let autoConnect = "autoConnect"
        static let autoReconnect = "autoReconnect"
        static let lastDeviceAddress = "lastDeviceAddress"
        static let showNotch = "showNotch"
        static let setupDone = "setupDone"
        static let usageMode = "usageMode"
        static let notchWidth = "notchOpenWidth"
        static let notchHeight = "notchOpenHeight"
        static let notchSide = "notchSideWidth"
        static let notchZoom = "notchZoom"
        static let notchArtwork = "notchRestingArtwork"
        static let swipeToSkip = "gestureSwipeToSkip"
        static let scrollForVolume = "gestureScrollForVolume"
        static let reverseSwipe = "gestureReverseSwipe"
        static let reverseScroll = "gestureReverseScroll"
        static let artworkGlow = "artworkGlow"
        static let progressRing = "progressRing"
        static let headphonesBattery = "headphonesBattery"
        static let glowSize = "glowSize"
        static let hapticOnOpen = "hapticOnOpen"
        static let hapticOnButtons = "hapticOnButtons"
        static let hapticOnSkip = "hapticOnSkip"
        static let hapticOnVolume = "hapticOnVolume"
        static let hapticStrength = "hapticStrength"
    }

    private let defaults: UserDefaults

    @Published var autoConnect: Bool {
        didSet { defaults.set(autoConnect, forKey: Keys.autoConnect) }
    }
    @Published var autoReconnect: Bool {
        didSet { defaults.set(autoReconnect, forKey: Keys.autoReconnect) }
    }
    // The setup assistant was closed once: it no longer opens at launch.
    var setupDone: Bool {
        get { defaults.bool(forKey: Keys.setupDone) }
        set { defaults.set(newValue, forKey: Keys.setupDone) }
    }
    // Notch only, headphones only, or both (setup window).
    @Published var usageMode: UsageMode { didSet { defaults.set(usageMode.rawValue, forKey: Keys.usageMode) } }
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
    // Options › Notch Gestures.
    @Published var swipeToSkip: Bool { didSet { defaults.set(swipeToSkip, forKey: Keys.swipeToSkip) } }
    @Published var scrollForVolume: Bool { didSet { defaults.set(scrollForVolume, forKey: Keys.scrollForVolume) } }
    @Published var reverseSwipe: Bool { didSet { defaults.set(reverseSwipe, forKey: Keys.reverseSwipe) } }
    @Published var reverseScroll: Bool { didSet { defaults.set(reverseScroll, forKey: Keys.reverseScroll) } }
    @Published var artworkGlow: Bool { didSet { defaults.set(artworkGlow, forKey: Keys.artworkGlow) } }
    @Published var progressRing: Bool { didSet { defaults.set(progressRing, forKey: Keys.progressRing) } }
    @Published var headphonesBattery: Bool { didSet { defaults.set(headphonesBattery, forKey: Keys.headphonesBattery) } }
    @Published var glowSize: Double { didSet { defaults.set(glowSize, forKey: Keys.glowSize) } }
    static let glowSizeRange: ClosedRange<CGFloat> = 0.5...1.75  // times the default glow size
    @Published var hapticOnOpen: Bool { didSet { defaults.set(hapticOnOpen, forKey: Keys.hapticOnOpen) } }
    @Published var hapticOnButtons: Bool { didSet { defaults.set(hapticOnButtons, forKey: Keys.hapticOnButtons) } }
    @Published var hapticOnSkip: Bool { didSet { defaults.set(hapticOnSkip, forKey: Keys.hapticOnSkip) } }
    @Published var hapticOnVolume: Bool { didSet { defaults.set(hapticOnVolume, forKey: Keys.hapticOnVolume) } }

    var anyHaptics: Bool { hapticOnOpen || hapticOnButtons || hapticOnSkip || hapticOnVolume }
    @Published var hapticStrength: Int { didSet { defaults.set(hapticStrength, forKey: Keys.hapticStrength) } }

    var gesturePreferences: NotchGesturePreferences {
        NotchGesturePreferences(swipeToSkip: swipeToSkip, scrollForVolume: scrollForVolume,
                                reverseSwipe: reverseSwipe, reverseScroll: reverseScroll)
    }

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
        // Auto-connect, auto-reconnect and the notch default on; launch at login stays off until the user asks.
        let layout = NotchLayout.default
        defaults.register(defaults: [
            Keys.autoConnect: true, Keys.autoReconnect: true, Keys.showNotch: true,
            Keys.notchWidth: Double(layout.openSize.width), Keys.notchHeight: Double(layout.openSize.height),
            Keys.notchSide: Double(layout.sideExtension), Keys.notchZoom: Double(layout.zoom),
            Keys.notchArtwork: Double(layout.restingArtwork),
            Keys.swipeToSkip: true, Keys.scrollForVolume: true, Keys.reverseSwipe: false, Keys.reverseScroll: false,
            Keys.artworkGlow: true, Keys.progressRing: true, Keys.headphonesBattery: true, Keys.glowSize: 1.0, Keys.hapticOnOpen: true, Keys.hapticOnButtons: true, Keys.hapticOnSkip: true, Keys.hapticOnVolume: true,
            Keys.hapticStrength: 2,
        ])
        autoConnect = defaults.bool(forKey: Keys.autoConnect)
        autoReconnect = defaults.bool(forKey: Keys.autoReconnect)
        showNotch = defaults.bool(forKey: Keys.showNotch)
        usageMode = UsageMode(stored: defaults.string(forKey: Keys.usageMode))
        notchWidth = defaults.double(forKey: Keys.notchWidth)
        notchHeight = defaults.double(forKey: Keys.notchHeight)
        notchSideWidth = defaults.double(forKey: Keys.notchSide)
        notchZoom = defaults.double(forKey: Keys.notchZoom)
        notchArtwork = defaults.double(forKey: Keys.notchArtwork)
        swipeToSkip = defaults.bool(forKey: Keys.swipeToSkip)
        scrollForVolume = defaults.bool(forKey: Keys.scrollForVolume)
        reverseSwipe = defaults.bool(forKey: Keys.reverseSwipe)
        reverseScroll = defaults.bool(forKey: Keys.reverseScroll)
        artworkGlow = defaults.bool(forKey: Keys.artworkGlow)
        progressRing = defaults.bool(forKey: Keys.progressRing)
        headphonesBattery = defaults.bool(forKey: Keys.headphonesBattery)
        glowSize = defaults.double(forKey: Keys.glowSize)
        hapticOnOpen = defaults.bool(forKey: Keys.hapticOnOpen)
        hapticOnButtons = defaults.bool(forKey: Keys.hapticOnButtons)
        hapticOnSkip = defaults.bool(forKey: Keys.hapticOnSkip)
        hapticOnVolume = defaults.bool(forKey: Keys.hapticOnVolume)
        hapticStrength = min(NotchHaptics.strengthRange.upperBound,
                             max(NotchHaptics.strengthRange.lowerBound, defaults.integer(forKey: Keys.hapticStrength)))
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
                    Keys.notchHeight, Keys.notchSide, Keys.notchZoom, Keys.notchArtwork, Keys.swipeToSkip,
                    Keys.scrollForVolume, Keys.reverseSwipe, Keys.reverseScroll]
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
