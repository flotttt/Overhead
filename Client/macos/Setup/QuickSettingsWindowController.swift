import AppKit
import SwiftUI

// The Quick Settings panel's window. Opened from the menu and from the notch, so always on a running
// app: closing it never quits anything.
final class QuickSettingsWindowController: NSObject, NSWindowDelegate {
    private let checks = SetupChecks()
    private let model: HeadphonesModel
    private let settings: AppSettings
    private let openFullSetup: () -> Void
    private var window: NSWindow?

    init(model: HeadphonesModel, settings: AppSettings, onPlayerGranted: @escaping () -> Void,
         openFullSetup: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.openFullSetup = openFullSetup
        checks.onPlayerGranted = onPlayerGranted
    }

    func show() {
        if window == nil {
            let view = QuickSettingsView(checks: checks, model: model, settings: settings,
                                         openFullSetup: { [weak self] in
                                             self?.window?.close()
                                             self?.openFullSetup()
                                         })
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = tr("Quick Settings")
            window.isReleasedWhenClosed = false
            window.delegate = self
            SetupWindowController.install(view, in: window)
            self.window = window
        }
        checks.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        checks.stop()
    }
}
