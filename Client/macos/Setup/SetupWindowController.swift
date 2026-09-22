import AppKit
import SwiftUI

// The setup assistant's window. The app has no Dock icon, so showing it also activates the app.
final class SetupWindowController: NSObject, NSWindowDelegate {
    private let checks = SetupChecks()
    private let model: HeadphonesModel
    private let settings: AppSettings
    private let music: MusicController
    private let onFinished: () -> Void
    private var window: NSWindow?
    private var builtRevisiting: Bool?   // the view is built for one mode; setupDone flips it once

    init(model: HeadphonesModel, settings: AppSettings, music: MusicController,
         onPlayerGranted: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.music = music
        self.onFinished = onFinished
        checks.onPlayerGranted = onPlayerGranted
    }

    // The assistant's final button: the setup is done, the app starts.
    func finish() {
        settings.setupDone = true
        onFinished()
        window?.close()
    }

    func show() {
        // The window is kept between openings, but the finished setup turns the assistant into a
        // freely navigable review: rebuild the view when that changed.
        if let window, builtRevisiting != settings.setupDone {
            window.contentView = NSHostingView(rootView: makeView())
            builtRevisiting = settings.setupDone
        }
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = tr("Overhead Setup")
            window.contentView = NSHostingView(rootView: makeView())
            builtRevisiting = settings.setupDone
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        checks.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // Closing early is not finishing: with no menu bar icon there would be no way back to the app,
    // so it quits. The setup starts over at the next launch.
    private func makeView() -> SetupView {
        SetupView(checks: checks, model: model, settings: settings, music: music,
                  revisiting: settings.setupDone,
                  showError: { [weak model] in model?.showError($0) },
                  finish: { [weak self] in self?.finish() })
    }

    func windowWillClose(_ notification: Notification) {
        checks.stop()
        settings.notchPreviewing = false
        if !settings.setupDone { NSApp.terminate(nil) }
    }
}
