import AppKit
import Combine
import SwiftUI

// The status item's menu. Built for the usage mode (rebuilt when it changes); update() refreshes states,
// visibility and values in place, including while the menu is open. Notch only: the notch settings and the app
// items. Headphones only: the headphones menu without the notch settings. Both: everything.
final class HeadphonesMenu {
    let menu = NSMenu()
    private let model: HeadphonesModel
    private let settings: AppSettings
    private let updates: UpdateChecker
    private var cancellables = Set<AnyCancellable>()

    private var errorItem = NSMenuItem()
    private var modeItems: [(SHCAmbientMode, NSMenuItem)] = []
    private var ambientRows: [NSMenuItem] = []            // level slider + focus on voice
    private var equalizerItem = NSMenuItem()
    private var equalizerRowItem = NSMenuItem()
    private var presetItems: [(Int, NSMenuItem)] = []
    private var equalizerNoteItem = NSMenuItem()
    private var equalizerResetItem = NSMenuItem()
    private var dseeItem = NSMenuItem()
    private var speakToChatItem = NSMenuItem()
    private var adaptiveVolumeItem = NSMenuItem()
    private var autoPowerOffItem = NSMenuItem()
    private var autoPowerOffItems: [NSMenuItem] = []
    private var aboutItem = NSMenuItem()
    private var aboutMenu = NSMenu()
    private var aboutValues: [String] = []  // cache to avoid rebuilding About menu on every slider drag
    private var connectItem = NSMenuItem()
    private var launchAtLoginItem = NSMenuItem()
    private var autoConnectItem = NSMenuItem()
    private var autoReconnectItem = NSMenuItem()
    private var showNotchItem = NSMenuItem()
    private var artworkGlowItem = NSMenuItem()
    private var progressRingItem = NSMenuItem()
    private var headphonesBatteryItem = NSMenuItem()
    private var glowItem = NSMenuItem()
    private var notchSizeItem = NSMenuItem()
    private var updateItem = NSMenuItem()
    private var gesturesItem = NSMenuItem()
    private var gestureItems: [(NSMenuItem, ReferenceWritableKeyPath<AppSettings, Bool>)] = []
    private let notchSizeMenuDelegate = NotchSizeMenuDelegate()
    var onOpenSetup: (() -> Void)?  // "Setup…": the setup assistant
    private let gesturesMenuDelegate = NotchSizeMenuDelegate()
    // SwiftUI sliders in a submenu stop taking clicks once the submenu has been closed and opened again, so their
    // rows are rebuilt each time their submenu opens (see sliderMenuItem).
    private var sliderRowBuilders: [ObjectIdentifier: () -> NSView?] = [:]

    private static var presets: [(Int, String)] {
        [(0x00, tr("Off")), (0x10, tr("Bright")), (0x11, tr("Excited")), (0x12, tr("Mellow")),
         (0x13, tr("Relaxed")), (0x14, tr("Vocal")), (0x15, tr("Treble")), (0x16, tr("Bass")),
         (0x17, tr("Speech")), (0xA0, tr("Manual"))]
    }

    // Index = the bridge's auto power-off option (0=Off, 1=5 min, 2=30 min, 3=1 h, 4=3 h, 5=when taken off).
    // Used for the submenu's item titles (long form).
    private static var autoPowerOffOptions: [String] {
        [tr("Off"), tr("5 min"), tr("30 min"), tr("1 hour"), tr("3 hours"), tr("When taken off")]
    }

    // Same options, but with a short last label - used for the value shown at the right of "Auto Power-Off"
    // itself, since the full "Quand le casque est retiré" collides with the title (the submenu keeps the long
    // label).
    private static var autoPowerOffShortOptions: [String] {
        var options = autoPowerOffOptions
        options[options.count - 1] = tr("Taken off")
        return options
    }

    init(model: HeadphonesModel, settings: AppSettings, updates: UpdateChecker) {
        self.model = model
        self.settings = settings
        self.updates = updates
        menu.autoenablesItems = false
        menu.minimumWidth = MenuMetrics.width

        build()
        settings.$usageMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.build() }
            .store(in: &cancellables)

        // objectWillChange fires before the new value is stored; hopping to the main queue reads the new state.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        updates.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        update()
    }

    // MARK: - Building

    private func build() {
        menu.removeAllItems()
        for item in [errorItem, equalizerItem, equalizerNoteItem, autoPowerOffItem, aboutItem, glowItem, notchSizeItem,
                     gesturesItem] {
            item.menu?.removeItem(item)
        }
        errorItem = NSMenuItem()
        equalizerItem = NSMenuItem()
        equalizerNoteItem = NSMenuItem()
        autoPowerOffItem = NSMenuItem()
        aboutItem = NSMenuItem()
        aboutMenu = NSMenu()
        aboutValues = []
        glowItem = NSMenuItem()
        notchSizeItem = NSMenuItem()
        gesturesItem = NSMenuItem()
        modeItems = []
        ambientRows = []
        presetItems = []
        autoPowerOffItems = []
        gestureItems = []
        sliderRowBuilders = [:]

        let mode = settings.usageMode
        if mode.usesHeadphones {
            menu.addItem(hostingMenuItem { HeaderRow(model: model) })
        } else {
            menu.addItem(sectionHeader("SonyNotch"))
        }
        errorItem.isEnabled = false
        menu.addItem(errorItem)
        menu.addItem(.separator())
        if mode.usesHeadphones {
            addAmbientSection()
            menu.addItem(.separator())
            addSoundSection()
            menu.addItem(.separator())
        } else {
            addNotchItems(to: menu)
            menu.addItem(.separator())
        }
        addAppSection(mode)
        update()
    }

    // The notch settings: in the Options submenu with headphones, at the top of the menu in notch-only mode.
    private func addNotchItems(to target: NSMenu) {
        showNotchItem = ActionMenuItem(tr("Show Notch")) { [weak settings] in settings?.showNotch.toggle() }
        target.addItem(showNotchItem)
        progressRingItem = ActionMenuItem(tr("Progress Ring")) { [weak settings] in settings?.progressRing.toggle() }
        target.addItem(progressRingItem)
        if settings.usageMode.usesHeadphones {
            headphonesBatteryItem = ActionMenuItem(tr("Headphones Battery")) { [weak settings] in
                settings?.headphonesBattery.toggle()
            }
            target.addItem(headphonesBatteryItem)
        }
        target.addItem(makeGlowItem())
        target.addItem(makeNotchSizeItem())
        target.addItem(makeGesturesItem())
    }

    private func addAmbientSection() {
        menu.addItem(sectionHeader(tr("Ambient Sound Control")))
        let modes: [(SHCAmbientMode, String)] = [
            (.noiseCanceling, tr("Noise Canceling")), (.ambientSound, tr("Ambient Sound")), (.off, tr("Off")),
        ]
        for (mode, title) in modes {
            let item = ActionMenuItem(title) { [weak model] in model?.setMode(mode) }
            item.image = NSImage(systemSymbolName: StatusIcon.symbolName(for: mode), accessibilityDescription: nil)
            modeItems.append((mode, item))
            menu.addItem(item)
            if mode == .ambientSound {
                ambientRows = [
                    hostingMenuItem { AmbientLevelRow(model: model) },
                    hostingMenuItem {
                        ToggleRow(model: model, title: tr("Focus on Voice"), indent: MenuMetrics.indent,
                                  isOn: { $0.focusOnVoice }, set: { $0.setFocusOnVoice($1) })
                    },
                ]
                ambientRows.forEach { menu.addItem($0) }
            }
        }
    }

    private func addSoundSection() {
        let equalizerMenu = NSMenu()
        equalizerMenu.autoenablesItems = false
        equalizerMenu.minimumWidth = MenuMetrics.equalizerWidth
        for (code, title) in Self.presets {
            let item = ActionMenuItem(title) { [weak model] in model?.setEqualizerPreset(code) }
            presetItems.append((code, item))
            equalizerMenu.addItem(item)
        }
        equalizerMenu.addItem(.separator())
        equalizerRowItem = hostingMenuItem(width: MenuMetrics.equalizerWidth) { EqualizerRow(model: model) }
        equalizerMenu.addItem(equalizerRowItem)
        equalizerNoteItem.title = tr("Equalizer changes coming soon for this model")
        equalizerNoteItem.isEnabled = false
        equalizerMenu.addItem(equalizerNoteItem)
        equalizerResetItem = ActionMenuItem(tr("Reset")) { [weak model] in model?.resetEqualizer() }
        equalizerMenu.addItem(equalizerResetItem)
        equalizerItem.submenu = equalizerMenu
        menu.addItem(equalizerItem)

        dseeItem = hostingMenuItem {
            ToggleRow(model: model, title: tr("DSEE"), isOn: { $0.dsee }, set: { $0.setDsee($1) })
        }
        speakToChatItem = hostingMenuItem {
            ToggleRow(model: model, title: tr("Speak-to-Chat"), isOn: { $0.speakToChat }, set: { $0.setSpeakToChat($1) })
        }
        adaptiveVolumeItem = hostingMenuItem {
            ToggleRow(model: model, title: tr("Adaptive Volume"), isOn: { $0.adaptiveVolume }, set: { $0.setAdaptiveVolume($1) })
        }
        for item in [dseeItem, speakToChatItem, adaptiveVolumeItem] { menu.addItem(item) }

        let autoPowerOffMenu = NSMenu()
        autoPowerOffMenu.autoenablesItems = false
        for (index, title) in Self.autoPowerOffOptions.enumerated() {
            let item = ActionMenuItem(title) { [weak model] in model?.setAutoPowerOff(index) }
            autoPowerOffItems.append(item)
            autoPowerOffMenu.addItem(item)
        }
        autoPowerOffItem.submenu = autoPowerOffMenu
        menu.addItem(autoPowerOffItem)
    }

    private func addAppSection(_ mode: UsageMode) {
        if mode.usesHeadphones {
            aboutItem.title = tr("About the Headphones")
            aboutMenu.autoenablesItems = false
            aboutItem.submenu = aboutMenu
            menu.addItem(aboutItem)
            let optionsMenu = NSMenu()
            optionsMenu.autoenablesItems = false
            autoConnectItem = ActionMenuItem(tr("Connect Automatically")) { [weak settings] in settings?.autoConnect.toggle() }
            autoReconnectItem = ActionMenuItem(tr("Reconnect Automatically")) { [weak settings] in settings?.autoReconnect.toggle() }
            optionsMenu.addItem(autoConnectItem)
            optionsMenu.addItem(autoReconnectItem)
            if mode.usesNotch {
                optionsMenu.addItem(.separator())
                addNotchItems(to: optionsMenu)
            }
            let optionsItem = NSMenuItem(title: tr("SonyNotch Options"), action: nil, keyEquivalent: "")
            optionsItem.submenu = optionsMenu
            menu.addItem(optionsItem)
            connectItem = ActionMenuItem(tr("Connect…")) { [weak self] in self?.toggleConnection() }
            menu.addItem(connectItem)
            menu.addItem(.separator())
        }
        launchAtLoginItem = ActionMenuItem(tr("Launch at Login")) { [weak self] in self?.toggleLaunchAtLogin() }
        menu.addItem(launchAtLoginItem)
        menu.addItem(ActionMenuItem(tr("Setup…")) { [weak self] in self?.onOpenSetup?() })
        updateItem = ActionMenuItem("") { [weak updates] in updates?.install() }
        menu.addItem(updateItem)
        menu.addItem(ActionMenuItem(tr("Quit SonyNotch"), key: "q") { NSApp.terminate(nil) })
    }

    // MARK: - Updating

    private func update() {
        let connected = model.connected

        errorItem.isHidden = model.errorMessage == nil
        errorItem.title = "⚠︎ " + (model.errorMessage ?? "")

        for (mode, item) in modeItems {
            item.state = connected && model.mode == mode ? .on : .off
            item.isEnabled = connected
        }
        ambientRows.forEach { $0.isHidden = model.mode != .ambientSound }

        equalizerItem.isHidden = !model.supportsEqualizer
        equalizerItem.isEnabled = connected
        equalizerItem.attributedTitle = titleWithValue(tr("Equalizer"), Self.presetName(model.eqPreset))
        for (code, item) in presetItems {
            item.state = model.eqPreset == code ? .on : .off
            item.isEnabled = connected && model.equalizerWritable
        }
        equalizerNoteItem.isHidden = model.equalizerWritable || model.eqBands.isEmpty
        equalizerRowItem.isHidden = model.eqBands.isEmpty
        equalizerResetItem.isEnabled = connected && model.equalizerWritable && model.eqPreset == 0xA0

        dseeItem.isHidden = !model.hasDsee
        speakToChatItem.isHidden = !model.hasSpeakToChat
        adaptiveVolumeItem.isHidden = !model.hasAdaptiveVolume

        let shortOptions = Self.autoPowerOffShortOptions
        autoPowerOffItem.isHidden = !model.hasAutoPowerOff
        autoPowerOffItem.isEnabled = connected
        autoPowerOffItem.attributedTitle = titleWithValue(
            tr("Auto Power-Off"),
            shortOptions.indices.contains(model.autoPowerOff) ? shortOptions[model.autoPowerOff] : "")
        for (index, item) in autoPowerOffItems.enumerated() {
            item.state = index == model.autoPowerOff ? .on : .off
        }

        updateAbout()
        aboutItem.isEnabled = connected

        switch model.connectionState {
        case .connected: connectItem.title = tr("Disconnect")
        case .connecting: connectItem.title = tr("Connecting…")
        case .disconnected: connectItem.title = tr("Connect…")
        }
        connectItem.isEnabled = model.connectionState != .connecting

        launchAtLoginItem.state = settings.launchAtLogin ? .on : .off
        autoConnectItem.state = settings.autoConnect ? .on : .off
        autoReconnectItem.state = settings.autoReconnect ? .on : .off
        showNotchItem.state = settings.showNotch ? .on : .off
        artworkGlowItem.state = settings.artworkGlow ? .on : .off
        glowItem.isEnabled = settings.showNotch
        progressRingItem.state = settings.progressRing ? .on : .off
        progressRingItem.isEnabled = settings.showNotch
        headphonesBatteryItem.state = settings.headphonesBattery ? .on : .off
        headphonesBatteryItem.isEnabled = settings.showNotch
        notchSizeItem.isEnabled = settings.showNotch
        gesturesItem.isEnabled = settings.showNotch
        for (item, keyPath) in gestureItems {
            item.state = settings[keyPath: keyPath] ? .on : .off
            // Reversing a gesture that is off means nothing. (Matched by setting, not position: the gestures
            // submenu doesn't exist in headphones-only mode.)
            if keyPath == \.reverseSwipe { item.isEnabled = settings.swipeToSkip }
            if keyPath == \.reverseScroll { item.isEnabled = settings.scrollForVolume }
        }
        // Always shown: greyed out while this is the latest version.
        if let release = updates.available {
            let version = release.tag.hasPrefix("v") ? String(release.tag.dropFirst()) : release.tag
            switch updates.state {
            case .idle: updateItem.title = String(format: tr("Update to SonyNotch %@"), version)
            case .installing: updateItem.title = tr("Updating SonyNotch…")
            case .failed: updateItem.title = String(format: tr("Update Failed, Download SonyNotch %@…"), version)
            }
            updateItem.isEnabled = updates.state != .installing
        } else {
            updateItem.title = String(format: tr("SonyNotch Is Up to Date (%@)"), updates.currentVersion)
            updateItem.isEnabled = false
        }
    }

    private func sliderMenuItem<Content: View>(width: CGFloat = MenuMetrics.width + 40,
                                               _ content: @escaping () -> Content) -> NSMenuItem {
        let item = hostingMenuItem(width: width, content)
        sliderRowBuilders[ObjectIdentifier(item)] = {
            let fresh = hostingMenuItem(width: width, content)
            let view = fresh.view
            fresh.view = nil
            return view
        }
        return item
    }

    private func rebuildSliderRows(in menu: NSMenu) {
        for item in menu.items {
            if let build = sliderRowBuilders[ObjectIdentifier(item)], let view = build() { item.view = view }
        }
    }

    // Options › Glow: the artwork-coloured glow behind the player and its size. Like Notch Size, the notch opens
    // as a preview while the submenu is open.
    private func makeGlowItem() -> NSMenuItem {
        let glowMenu = NSMenu()
        glowMenu.autoenablesItems = false
        notchSizeMenuDelegate.settings = settings
        notchSizeMenuDelegate.willOpen = { [weak self] menu in self?.rebuildSliderRows(in: menu) }
        glowMenu.delegate = notchSizeMenuDelegate
        artworkGlowItem = ActionMenuItem(tr("Artwork Glow")) { [weak settings] in settings?.artworkGlow.toggle() }
        glowMenu.addItem(artworkGlowItem)
        glowMenu.addItem(sliderMenuItem { [settings] in
            NotchSizeRow(settings: settings, title: tr("Glow Size"), keyPath: \.glowSize,
                         range: AppSettings.glowSizeRange, format: { "\(Int(($0 * 100).rounded())) %" })
        })
        glowMenu.addItem(.separator())
        glowMenu.addItem(ActionMenuItem(tr("Reset Size")) { [weak settings] in settings?.glowSize = 1 })
        glowItem.title = tr("Glow")
        glowItem.submenu = glowMenu
        return glowItem
    }

    // Options › Notch Gestures: turn the swipe and scroll gestures on or off, or reverse them.
    private func makeGesturesItem() -> NSMenuItem {
        let gesturesMenu = NSMenu()
        gesturesMenu.autoenablesItems = false
        let rows: [(String, ReferenceWritableKeyPath<AppSettings, Bool>)] = [
            (tr("Swipe to Change Track"), \.swipeToSkip),
            (tr("Scroll to Change Volume"), \.scrollForVolume),
            (tr("Reverse Swipe Direction"), \.reverseSwipe),
            (tr("Reverse Scroll Direction"), \.reverseScroll),
            (tr("When the Notch Opens"), \.hapticOnOpen),
            (tr("On Buttons"), \.hapticOnButtons),
            (tr("When Changing Track"), \.hapticOnSkip),
            (tr("On Volume Steps"), \.hapticOnVolume),
        ]
        for (title, keyPath) in rows {
            if keyPath == \.reverseSwipe { gesturesMenu.addItem(.separator()) }
            if keyPath == \.hapticOnOpen {
                gesturesMenu.addItem(.separator())
                gesturesMenu.addItem(Self.submenuHeader(tr("Haptic Feedback")))
            }
            let item = ActionMenuItem(title) { [weak settings] in settings?[keyPath: keyPath].toggle() }
            gestureItems.append((item, keyPath))
            gesturesMenu.addItem(item)
        }
        gesturesMenu.addItem(sliderMenuItem(width: MenuMetrics.width) { [settings] in HapticStrengthRow(settings: settings) })
        gesturesMenuDelegate.previewsNotch = false
        gesturesMenuDelegate.willOpen = { [weak self] menu in self?.rebuildSliderRows(in: menu) }
        gesturesMenu.delegate = gesturesMenuDelegate
        gesturesItem.title = tr("Notch Gestures")
        gesturesItem.submenu = gesturesMenu
        return gesturesItem
    }

    private static func submenuHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return .sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // Options › Notch Size: sliders applied live, the notch staying open as a preview while the submenu is open.
    private func makeNotchSizeItem() -> NSMenuItem {
        let sizeMenu = NSMenu()
        sizeMenu.autoenablesItems = false
        notchSizeMenuDelegate.settings = settings
        notchSizeMenuDelegate.willOpen = { [weak self] menu in self?.rebuildSliderRows(in: menu) }
        sizeMenu.delegate = notchSizeMenuDelegate
        let points: (Double) -> String = { String(Int($0.rounded())) }
        let percent: (Double) -> String = { "\(Int(($0 * 100).rounded())) %" }
        let rows: [(String, ReferenceWritableKeyPath<AppSettings, Double>, ClosedRange<CGFloat>, (Double) -> String)] = [
            (tr("Open Width"), \.notchWidth, NotchLayout.widthRange, points),
            (tr("Open Height"), \.notchHeight, NotchLayout.heightRange, points),
            (tr("Closed Width"), \.notchSideWidth, NotchLayout.sideRange, points),
            (tr("Closed Artwork"), \.notchArtwork, NotchLayout.artworkRange, points),
            (tr("Text Size"), \.notchZoom, NotchLayout.zoomRange, percent),
        ]
        for (title, keyPath, range, format) in rows {
            sizeMenu.addItem(sliderMenuItem { [settings] in
                NotchSizeRow(settings: settings, title: title, keyPath: keyPath, range: range, format: format)
            })
        }
        sizeMenu.addItem(.separator())
        sizeMenu.addItem(ActionMenuItem(tr("Reset Size")) { [weak settings] in settings?.resetNotchSize() })
        notchSizeItem.title = tr("Notch Size")
        notchSizeItem.submenu = sizeMenu
        return notchSizeItem
    }

    private func updateAbout() {
        // update() runs on every model change (slider drags included); rebuild only when a value changed.
        let values = [model.firmware, model.codec, model.protocolVersion, model.deviceMac]
        guard values != aboutValues else { return }
        aboutValues = values

        aboutMenu.removeAllItems()
        let rows: [(String, String)] = [
            (tr("Firmware"), model.firmware), (tr("Codec"), model.codec),
            (tr("Protocol"), model.protocolVersion), (tr("Bluetooth"), model.deviceMac),
        ]
        for (title, value) in rows where !value.isEmpty {
            let item = NSMenuItem()
            item.attributedTitle = titleWithValue(title, value)
            item.isEnabled = false
            aboutMenu.addItem(item)
        }
    }

    private static func presetName(_ code: Int) -> String {
        presets.first { $0.0 == code }?.1 ?? tr("Custom")
    }

    private func toggleLaunchAtLogin() {
        if let error = settings.setLaunchAtLogin(!settings.launchAtLogin) { model.showError(error) }
    }

    private func toggleConnection() {
        if model.connected {
            model.disconnect()
        } else {
            NSApp.activate(ignoringOtherApps: true) // the fallback Bluetooth picker is a modal window
            model.connect()
        }
    }
}

// Opens the notch as a live preview while the Notch Size submenu is open.
private final class NotchSizeMenuDelegate: NSObject, NSMenuDelegate {
    weak var settings: AppSettings?
    var previewsNotch = true
    var willOpen: ((NSMenu) -> Void)?

    func menuWillOpen(_ menu: NSMenu) {
        willOpen?(menu)
        if previewsNotch { settings?.notchPreviewing = true }
    }

    func menuDidClose(_ menu: NSMenu) {
        if previewsNotch { settings?.notchPreviewing = false }
    }
}
