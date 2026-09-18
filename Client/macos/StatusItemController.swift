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
    private var cancellables = Set<AnyCancellable>()

    init(model: HeadphonesModel, settings: AppSettings, updates: UpdateChecker) {
        headphonesMenu = HeadphonesMenu(model: model, settings: settings, updates: updates)
        statusItem.menu = headphonesMenu.menu
        model.$connectionState.combineLatest(model.$mode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, mode in
                let connected = state == .connected
                self?.statusItem.button?.image = StatusIcon.image(connected: connected, mode: mode)
                self?.statusItem.button?.appearsDisabled = !connected
            }
            .store(in: &cancellables)
    }
}
