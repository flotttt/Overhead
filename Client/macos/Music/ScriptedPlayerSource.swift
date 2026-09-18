import AppKit

// Reads and controls a music app of this Mac that speaks AppleScript (Spotify, Music): its playback signal, plus
// Apple Events. Never sends an Apple Event while the app isn't running: one would launch it.
final class ScriptedPlayerSource: MusicSource {
    private static let permissionDeniedError = -1743           // errAEEventNotPermitted
    private static let notRunningErrors: Set<Int> = [-600, -609]  // procNotFound, connectionInvalid
    private static let launchSettleDelay: TimeInterval = 2     // apps answer Apple Events a moment after launch

    let player: ScriptedPlayer
    var onChange: ((MusicSourceStatus, NowPlaying?) -> Void)?

    var id: String { player.id }
    var playerName: String { player.name }
    var bundleIdentifier: String { player.bundleIdentifier }

    // Main thread only.
    private var status: MusicSourceStatus = .notRunning
    private var nowPlaying: NowPlaying?
    private var signalObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    // Every NSAppleScript of every player is created and run on this one serial queue: NSAppleScript isn't
    // thread-safe, and two scripts running at once can get each other's reply (Music read Spotify's state while
    // it waited on a stuck Music).
    private static let sharedScriptQueue = DispatchQueue(label: "com.sonynotch.players")
    private var scriptQueue: DispatchQueue { Self.sharedScriptQueue }
    private var readScript: NSAppleScript?     // scriptQueue only
    private var artworkScript: NSAppleScript?  // scriptQueue only
    private var consentGranted = false         // scriptQueue only

    init(player: ScriptedPlayer) {
        self.player = player
    }

    // Checked before queuing, and again on the script queue right before an Apple Event goes out, so an app quit
    // in between is never relaunched.
    private static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private var isRunning: Bool { Self.isRunning(player.bundleIdentifier) }

    func start() {
        guard signalObserver == nil else { return }
        signalObserver = DistributedNotificationCenter.default().addObserver(
            forName: player.signalName, object: nil, queue: .main
        ) { [weak self] note in
            self?.handleSignal(note.userInfo)
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self = self, self.isPlayer(note) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchSettleDelay) { [weak self] in self?.refresh() }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self = self, self.isPlayer(note) else { return }
                self.publish(.notRunning, nil)
            },
        ]
        if isRunning { refresh() } else { publish(.notRunning, nil) }
    }

    func stop() {
        if let observer = signalObserver { DistributedNotificationCenter.default().removeObserver(observer) }
        signalObserver = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers = []
        status = .notRunning
        nowPlaying = nil
    }

    func refresh() {
        guard signalObserver != nil else { return }
        guard isRunning else { publish(.notRunning, nil); return }
        let bundleIdentifier = player.bundleIdentifier
        let source = player.readScript
        scriptQueue.async { [weak self] in
            guard let self = self, Self.isRunning(bundleIdentifier) else { return }
            if let code = self.consentError() {
                DispatchQueue.main.async { self.applyFailure(code) }
                return
            }
            if self.readScript == nil { self.readScript = NSAppleScript(source: source) }
            let result = PlayerScript.run(self.readScript)
            DispatchQueue.main.async { self.applyRead(result) }
        }
    }

    func playPause() {
        // Optimistic: the signal confirms a moment later.
        if var track = nowPlaying {
            track.position = PlaybackClock.position(of: track, at: Date())
            track.positionDate = Date()
            track.isPlaying.toggle()
            publish(status, track)
        }
        send("playpause")
    }

    func next() { send("next track") }

    func previous() { send("previous track") }

    func seek(to seconds: TimeInterval) {
        if var track = nowPlaying {
            track.position = seconds
            track.positionDate = Date()
            publish(status, track)
        }
        // String(format:) isn't localized: always a "." decimal separator, as AppleScript source needs.
        send(String(format: "set player position to %.3f", seconds))
    }

    func setVolume(_ volume: Int) {
        let clamped = min(100, max(0, volume))
        if var track = nowPlaying {
            track.volume = clamped
            publish(status, track)
        }
        send("set sound volume to \(clamped)")
    }

    func launchPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) else {
            fputs("[\(player.id)] \(player.name) isn't installed\n", stderr)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }

    // MARK: - Private

    private func send(_ command: String) {
        guard signalObserver != nil else { return }
        guard isRunning else { publish(.notRunning, nil); return }
        let bundleIdentifier = player.bundleIdentifier
        scriptQueue.async { [weak self] in
            guard let self = self, Self.isRunning(bundleIdentifier) else { return }
            if let code = self.consentError() {
                DispatchQueue.main.async { self.applyFailure(code) }
                return
            }
            let result = PlayerScript.run(NSAppleScript(source: PlayerScript.command(command, app: bundleIdentifier)))
            if case .failure(let code) = result {
                DispatchQueue.main.async { self.applyFailure(code) }
            }
        }
    }

    private func handleSignal(_ userInfo: [AnyHashable: Any]?) {
        let denied = status == .permissionDenied
        switch player.parseSignal(userInfo, Date()) {
        case .stopped:
            publish(denied ? .permissionDenied : .ready, nil)
        case .track(var track):
            // Artwork and volume only come from Apple Events: keep them for the same track, read them otherwise.
            keepAppleEventDetails(of: &track)
            publish(denied ? .permissionDenied : .ready, track)
            if track.artworkURL == nil && track.artworkData == nil && !denied { refresh() }
        case .incomplete:
            if !denied { refresh() }
        }
    }

    private func keepAppleEventDetails(of track: inout NowPlaying) {
        guard let current = nowPlaying, current.trackID == track.trackID else { return }
        if track.artworkURL == nil { track.artworkURL = current.artworkURL }
        if track.artworkData == nil { track.artworkData = current.artworkData }
        if track.volume == nil { track.volume = current.volume }
    }

    private func applyRead(_ result: PlayerScript.Result) {
        guard signalObserver != nil else { return }  // stopped meanwhile
        switch result {
        case .success(let text):
            switch player.parseRead(text, Date()) {
            case .stopped:
                publish(.ready, nil)
            case .track(var track):
                keepAppleEventDetails(of: &track)
                publish(.ready, track)
                if track.artworkURL == nil && track.artworkData == nil { readArtwork(for: track.trackID) }
            case .incomplete:
                fputs("[\(player.id)] unexpected reply: \(text)\n", stderr)
            }
        case .failure(let code):
            applyFailure(code)
        }
    }

    // Players whose artwork is image data (Music): read once per track, after the rest.
    private func readArtwork(for trackID: String) {
        guard let source = player.artworkScript else { return }
        let bundleIdentifier = player.bundleIdentifier
        scriptQueue.async { [weak self] in
            guard let self = self, Self.isRunning(bundleIdentifier), self.consentGranted else { return }
            if self.artworkScript == nil { self.artworkScript = NSAppleScript(source: source) }
            let data = PlayerScript.runData(self.artworkScript)
            DispatchQueue.main.async {
                guard let data = data, var track = self.nowPlaying, track.trackID == trackID else { return }
                track.artworkData = data
                self.publish(self.status, track)
            }
        }
    }

    // A refusal stops the reads (the controller retries once per notch opening); anything else
    // (timeout, busy) keeps the last known state until the next signal.
    private func applyFailure(_ code: Int) {
        guard signalObserver != nil else { return }
        if code == Self.permissionDeniedError {
            publish(.permissionDenied, nowPlaying)
        } else if Self.notRunningErrors.contains(code) {
            publish(.notRunning, nil)
        } else {
            fputs("[\(player.id)] Apple Event failed (\(code))\n", stderr)
        }
    }

    // scriptQueue only. Asks for macOS's automation consent without a timeout: otherwise the scripts' own 2 s
    // timeout cancels the first Apple Event while the consent prompt still waits for the user, and the read is
    // lost. nil = allowed; otherwise the error to handle (-1743 refused, -600 not running).
    private func consentError() -> Int? {
        if consentGranted { return nil }
        let target = NSAppleEventDescriptor(bundleIdentifier: player.bundleIdentifier)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), true)
        if status == noErr {
            consentGranted = true
            return nil
        }
        return Int(status)
    }

    private func publish(_ newStatus: MusicSourceStatus, _ track: NowPlaying?) {
        status = newStatus
        nowPlaying = track
        onChange?(newStatus, track)
    }

    private func isPlayer(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            == player.bundleIdentifier
    }
}
