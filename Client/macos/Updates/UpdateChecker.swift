import AppKit
import Combine
import CryptoKit

// Asks GitHub for the latest release at launch and then once a day, and publishes it when it's newer than this
// app. install() downloads it, checks its SHA-256, replaces this app and relaunches it. When that isn't possible
// (no zip in the release, app folder not writable), the release page opens instead.
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case installing
        case failed
    }

    private enum InstallError: Error {
        case download(Int)
        case checksum
        case unexpectedApp
        case command(String)
    }

    private static let interval: TimeInterval = 24 * 60 * 60

    @Published private(set) var available: LatestRelease?
    @Published private(set) var state: State = .idle

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func start() {
        guard timer == nil else { return }
        check()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func openReleasePage() {
        if let url = available?.pageURL { NSWorkspace.shared.open(url) }
    }

    // Main thread.
    func install() {
        guard let release = available, state != .installing else { return }
        guard state != .failed, let zipURL = release.appZipURL, let checksumURL = release.checksumURL,
              canReplaceApp else {
            openReleasePage()
            return
        }
        state = .installing
        fputs("[updates] installing \(release.tag)\n", stderr)
        // The download and the swap run off the main actor (downloadAndReplace isn't isolated); the result comes back
        // here.
        Task { @MainActor [weak self] in
            do {
                let app = try await Self.downloadAndReplace(release, zipURL: zipURL, checksumURL: checksumURL)
                Self.relaunch(app)
            } catch {
                fputs("[updates] install failed: \(error)\n", stderr)
                self?.state = .failed
            }
        }
    }

    // The folder holding the app must be writable (not the case for a translocated or read-only copy).
    private var canReplaceApp: Bool {
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    private func check() {
        var request = URLRequest(url: ReleaseInfo.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            // A failed check (offline, rate limit) keeps what we knew; the next one tries again.
            guard let data = data, (response as? HTTPURLResponse)?.statusCode == 200 else {
                fputs("[updates] check failed (\((response as? HTTPURLResponse)?.statusCode ?? 0))\n", stderr)
                return
            }
            let latest = ReleaseInfo.parse(json: data)
            DispatchQueue.main.async {
                guard let self = self, self.state != .installing else { return }
                let update = ReleaseInfo.update(currentVersion: self.currentVersion, latest: latest)
                if update != self.available { self.state = .idle }
                self.available = update
                fputs("[updates] running \(self.currentVersion), latest \(latest?.tag ?? "?")\(update != nil ? ", update available" : "")\n", stderr)
            }
        }.resume()
    }

    // Downloads the zip, checks it against the release's .sha256, unzips it next to the app (same volume, so the
    // swap is a rename) and swaps the bundles. Returns the installed app.
    private static func downloadAndReplace(_ release: LatestRelease, zipURL: URL, checksumURL: URL) async throws -> URL {
        let (checksumData, checksumResponse) = try await URLSession.shared.data(from: checksumURL)
        try requireOK(checksumResponse)
        guard let expected = ReleaseInfo.checksum(fromFile: String(decoding: checksumData, as: UTF8.self)) else {
            throw InstallError.checksum
        }

        let (downloaded, zipResponse) = try await URLSession.shared.download(from: zipURL)
        try requireOK(zipResponse)
        let actual = SHA256.hash(data: try Data(contentsOf: downloaded)).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw InstallError.checksum }

        let fileManager = FileManager.default
        let current = Bundle.main.bundleURL
        let work = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                       appropriateFor: current, create: true)
        defer { try? fileManager.removeItem(at: work) }
        let zip = work.appendingPathComponent(ReleaseInfo.appZipName)
        try fileManager.moveItem(at: downloaded, to: zip)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

        // Only ever install SonyNotch itself, in the version announced.
        let newApp = work.appendingPathComponent("SonyNotch.app")
        guard let bundle = Bundle(url: newApp), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              AppVersion(version) == release.version else {
            throw InstallError.unexpectedApp
        }
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        return try fileManager.replaceItemAt(current, withItemAt: newApp) ?? current
    }

    private static func requireOK(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw InstallError.download(status) }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError.command(tool) }
    }

    // A shell waits for this process to exit, then opens the new app through LaunchServices.
    private static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                             app.path]
        try? process.run()
        fputs("[updates] installed, relaunching\n", stderr)
        NSApp.terminate(nil)
    }
}
