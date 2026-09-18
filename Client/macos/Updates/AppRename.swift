import AppKit
import ServiceManagement

// The app was called SonyBridge, then SonyNotch. The updater of those versions installs Overhead at their own path
// (/Applications/SonyNotch.app, from the SonyNotch.zip every release carries): the first launch from there renames
// the bundle to Overhead.app and starts again from it. Launch at login is moved along.
enum AppRename {
    static let formerBundleNames: Set<String> = ["SonyNotch.app", "SonyBridge.app"]
    static let bundleName = "Overhead.app"
    private static let reRegisterLoginItemKey = "renameReRegisterLoginItem"

    // Where the bundle at this URL should move: nil when it already has the right name. Pure, tested in LogicTests.
    static func renamedURL(for bundle: URL) -> URL? {
        guard formerBundleNames.contains(bundle.lastPathComponent) else { return nil }
        return bundle.deletingLastPathComponent().appendingPathComponent(bundleName)
    }

    // Before anything else at launch. True: the renamed copy is starting, this process must quit.
    static func moveIfNeeded() -> Bool {
        let fileManager = FileManager.default
        let current = Bundle.main.bundleURL
        guard let target = renamedURL(for: current), !fileManager.fileExists(atPath: target.path),
              fileManager.isWritableFile(atPath: current.deletingLastPathComponent().path) else { return false }
        let loginItem = SMAppService.mainApp.status == .enabled
        if loginItem { try? SMAppService.mainApp.unregister() }
        do {
            try fileManager.moveItem(at: current, to: target)
        } catch {
            fputs("[rename] can't rename \(current.lastPathComponent): \(error.localizedDescription)\n", stderr)
            if loginItem { try? SMAppService.mainApp.register() }
            return false
        }
        if loginItem { UserDefaults.standard.set(true, forKey: reRegisterLoginItemKey) }

        // A new instance: this one, same bundle identifier, is still running. Same arguments (the log file).
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = Array(CommandLine.arguments.dropFirst())
        let launched = DispatchSemaphore(value: 0)  // the completion handler runs on another queue
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, error in
            if let error = error { fputs("[rename] relaunch failed: \(error.localizedDescription)\n", stderr) }
            launched.signal()
        }
        _ = launched.wait(timeout: .now() + 10)
        return true
    }

    // In the renamed copy: launch at login again, now pointing at Overhead.app.
    static func finishIfNeeded() {
        guard UserDefaults.standard.bool(forKey: reRegisterLoginItemKey) else { return }
        UserDefaults.standard.removeObject(forKey: reRegisterLoginItemKey)
        do {
            try SMAppService.mainApp.register()
        } catch {
            fputs("[rename] launch at login not restored: \(error.localizedDescription)\n", stderr)
        }
    }
}
