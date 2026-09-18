import AppKit
import SwiftUI

// The setup assistant's window. The app has no Dock icon, so showing it also activates the app.
final class SetupWindowController: NSObject, NSWindowDelegate {
    private let checks = SetupChecks()
    private let model: HeadphonesModel
    private let settings: AppSettings
    private var window: NSWindow?

    init(model: HeadphonesModel, settings: AppSettings, onPlayerGranted: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        checks.onPlayerGranted = onPlayerGranted
    }

    func show() {
        if window == nil {
            let view = SetupView(checks: checks, model: model, settings: settings,
                                 showError: { [weak model] in model?.showError($0) },
                                 done: { [weak self] in self?.window?.close() })
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = tr("Overhead Setup")
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        checks.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        checks.stop()
        settings.setupDone = true
    }
}
