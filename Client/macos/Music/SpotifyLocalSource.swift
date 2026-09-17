import AppKit

// Reads and controls the Spotify app of this Mac (spec §6): its PlaybackStateChanged signal, plus Apple Events.
// Never sends an Apple Event while Spotify isn't running: one would launch it.
final class SpotifyLocalSource: MusicSource {
    static let bundleIdentifier = "com.spotify.client"
    private static let signalName = Notification.Name("com.spotify.client.PlaybackStateChanged")
    private static let permissionDeniedError = -1743           // errAEEventNotPermitted
    private static let notRunningErrors: Set<Int> = [-600, -609]  // procNotFound, connectionInvalid
    private static let launchSettleDelay: TimeInterval = 2     // Spotify answers Apple Events a moment after launch

    var onChange: ((MusicSourceStatus, NowPlaying?) -> Void)?

    // Main thread only.
    private var status: MusicSourceStatus = .notRunning
    private var nowPlaying: NowPlaying?
    private var signalObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    // Every NSAppleScript is created and run on this serial queue, one at a time.
    private let scriptQueue = DispatchQueue(label: "com.sonynotch.spotify")
    private var readScript: NSAppleScript?  // scriptQueue only
    private var consentGranted = false  // scriptQueue only

    // Checked before queuing, and again on the script queue right before an Apple Event goes out, so a Spotify
    // quit in between is never relaunched.
    private static var spotifyIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private var isRunning: Bool { Self.spotifyIsRunning }

    func start() {
        guard signalObserver == nil else { return }
        signalObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.signalName, object: nil, queue: .main
        ) { [weak self] note in
            self?.handleSignal(note.userInfo)
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard Self.isSpotify(note) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchSettleDelay) { self?.refresh() }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                if Self.isSpotify(note) { self?.publish(.notRunning, nil) }
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
        scriptQueue.async { [weak self] in
            guard let self = self, Self.spotifyIsRunning else { return }
            if let code = self.consentError() {
                DispatchQueue.main.async { self.applyFailure(code) }
                return
            }
            if self.readScript == nil { self.readScript = NSAppleScript(source: SpotifyScript.readState) }
            let result = SpotifyScript.run(self.readScript)
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
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            fputs("[spotify] Spotify isn't installed\n", stderr)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }

    // MARK: - Private

    private func send(_ command: String) {
        guard signalObserver != nil else { return }
        guard isRunning else { publish(.notRunning, nil); return }
        scriptQueue.async { [weak self] in
            guard let self = self, Self.spotifyIsRunning else { return }
            if let code = self.consentError() {
                DispatchQueue.main.async { self.applyFailure(code) }
                return
            }
            let result = SpotifyScript.run(NSAppleScript(source: SpotifyScript.command(command)))
            if case .failure(let code) = result {
                DispatchQueue.main.async { self.applyFailure(code) }
            }
        }
    }

    private func handleSignal(_ userInfo: [AnyHashable: Any]?) {
        let denied = status == .permissionDenied
        switch SpotifyPlaybackInfo.parse(signal: userInfo, at: Date()) {
        case .stopped:
            publish(denied ? .permissionDenied : .ready, nil)
        case .track(var track):
            // Artwork and volume only come from Apple Events: keep them for the same track, read them otherwise.
            if let current = nowPlaying, current.trackID == track.trackID {
                track.artworkURL = current.artworkURL
                track.volume = current.volume
            }
            publish(denied ? .permissionDenied : .ready, track)
            if track.artworkURL == nil && !denied { refresh() }
        case .incomplete:
            if !denied { refresh() }
        }
    }

    private func applyRead(_ result: SpotifyScript.Result) {
        guard signalObserver != nil else { return }  // stopped meanwhile
        switch result {
        case .success(let text):
            switch SpotifyPlaybackInfo.parse(scriptResult: text, at: Date()) {
            case .stopped: publish(.ready, nil)
            case .track(let track): publish(.ready, track)
            case .incomplete: fputs("[spotify] unexpected reply: \(text)\n", stderr)
            }
        case .failure(let code):
            applyFailure(code)
        }
    }

    // Spec §6.3: a refusal stops the reads (the controller retries once per notch opening); anything else
    // (timeout, busy) keeps the last known state until the next signal.
    private func applyFailure(_ code: Int) {
        guard signalObserver != nil else { return }
        if code == Self.permissionDeniedError {
            publish(.permissionDenied, nowPlaying)
        } else if Self.notRunningErrors.contains(code) {
            publish(.notRunning, nil)
        } else {
            fputs("[spotify] Apple Event failed (\(code))\n", stderr)
        }
    }

    // scriptQueue only. Asks for macOS's automation consent without a timeout: otherwise the scripts' own 2 s
    // timeout cancels the first Apple Event while the consent prompt still waits for the user, and the read is
    // lost. nil = allowed; otherwise the error to handle (-1743 refused, -600 Spotify not running).
    private func consentError() -> Int? {
        if consentGranted { return nil }
        let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleIdentifier)
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

    private static func isSpotify(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleIdentifier
    }
}
