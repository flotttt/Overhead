import AppKit
import Combine

// Owns the menu bar icon (it follows the mode and connection state) and attaches the headphones menu to it.
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let headphonesMenu: HeadphonesMenu

    var onOpenSetup: (() -> Void)? {
        get { headphonesMenu.onOpenSetup }
        set { headphonesMenu.onOpenSetup = newValue }
    }
    var onOpenQuickSettings: (() -> Void)? {
        get { headphonesMenu.onOpenQuickSettings }
        set { headphonesMenu.onOpenQuickSettings = newValue }
    }
    private var cancellables = Set<AnyCancellable>()

    init(model: HeadphonesModel, settings: AppSettings, updates: UpdateChecker) {
        headphonesMenu = HeadphonesMenu(model: model, settings: settings, updates: updates)
        statusItem.menu = headphonesMenu.menu
        // Notch only: the app's mark. Otherwise the headphones' mode, dimmed while disconnected.
        model.$connectionState.combineLatest(model.$mode, settings.$usageMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, mode, usage in
                guard let button = self?.statusItem.button else { return }
                if usage.usesHeadphones {
                    let connected = state == .connected
                    button.image = StatusIcon.image(connected: connected, mode: mode)
                    button.appearsDisabled = !connected
                } else {
                    button.image = StatusIcon.appMark
                    button.appearsDisabled = false
                }
            }
            .store(in: &cancellables)
    }
}
