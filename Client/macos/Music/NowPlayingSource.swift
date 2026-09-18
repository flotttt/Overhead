import AppKit

// Every other player (Deezer, YouTube Music, browsers…), through macOS's "Now Playing": NowPlayingHelper runs
// inside /usr/bin/perl, streams the changes as JSON lines and takes commands on its input. Experimental (it relies
// on private MediaRemote calls and on perl), and off with Options › Other Players. Spotify and Music keep their own
// source: what Now Playing says about them is ignored here. No volume: Now Playing doesn't give one.
final class NowPlayingSource: MusicSource {
    private static let helperName = "NowPlayingHelper.dylib"
    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    // Loads the helper, then calls its entry point (not from the library's load, which holds dyld's lock).
    private static let perlScript = """
        use DynaLoader;
        my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        my $run = DynaLoader::dl_find_symbol($lib, "overhead_now_playing_run") or die DynaLoader::dl_error();
        DynaLoader::dl_install_xsub("main::run", $run);
        run();
        """
    private static let restartDelay: TimeInterval = 5
    private static let maxQuickFailures = 3  // then give up until the next start (a helper that can't work)
    private static let quickFailure: TimeInterval = 10

    let id = "now-playing"
    let bundleIdentifier = ""  // follows whichever app plays
    var onChange: ((MusicSourceStatus, NowPlaying?) -> Void)?
    private(set) var playerName = ""

    // Off: the helper doesn't run. Set by the Other Players option.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue, running else { return }
            if isEnabled { launchHelper() } else { stopHelper(); publish(nil) }
        }
    }

    // Main thread only.
    private var running = false
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var bundleID: String?
    private var nowPlaying: NowPlaying?
    private var launchedAt = Date.distantPast
    private var quickFailures = 0

    // Apps with a source of their own.
    private let nativeBundleIDs = Set(ScriptedPlayer.all.map(\.bundleIdentifier))

    func start() {
        guard !running else { return }
        running = true
        quickFailures = 0
        publish(nil)
        if isEnabled { launchHelper() }
    }

    func stop() {
        guard running else { return }
        running = false
        stopHelper()
        nowPlaying = nil
        bundleID = nil
    }

    // The helper pushes every change: nothing to read.
    func refresh() {}

    func playPause() {
        // Optimistic: the helper confirms a moment later.
        if var track = nowPlaying {
            track.position = PlaybackClock.position(of: track, at: Date())
            track.positionDate = Date()
            track.isPlaying.toggle()
            nowPlaying = track
            publish(track)
        }
        send("toggle")
    }

    func next() { send("next") }

    func previous() { send("previous") }

    func seek(to seconds: TimeInterval) {
        if var track = nowPlaying {
            track.position = seconds
            track.positionDate = Date()
            nowPlaying = track
            publish(track)
        }
        send(String(format: "seek %.3f", seconds))  // not localized: always a "." decimal separator
    }

    func setVolume(_ volume: Int) {}

    // Brings the app that plays to the front (a browser: its window, not the tab).
    func launchPlayer() {
        guard let bundleID = bundleID else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }

    private func launchHelper() {
        guard process == nil else { return }
        // Writing a command to a helper that just ended must fail with an error, not kill Overhead.
        signal(SIGPIPE, SIG_IGN)
        guard let helper = Bundle.main.privateFrameworksURL?.appendingPathComponent(Self.helperName),
              FileManager.default.fileExists(atPath: helper.path) else {
            fputs("[now-playing] \(Self.helperName) is missing from the app\n", stderr)
            return
        }
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = ["-e", Self.perlScript, helper.path]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.received(data) }
        }
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async { self?.helperEnded(ended) }
        }
        do {
            try process.run()
        } catch {
            fputs("[now-playing] can't start perl: \(error.localizedDescription)\n", stderr)
            return
        }
        self.process = process
        self.input = input.fileHandleForWriting
        buffer = Data()
        launchedAt = Date()
    }

    // Closing its input makes the helper exit by itself.
    private func stopHelper() {
        guard let process = process else { return }
        self.process = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        input = nil
        if process.isRunning { process.terminate() }
    }

    private func helperEnded(_ ended: Process) {
        guard ended === process else { return }  // stopped on purpose
        process = nil
        input = nil
        fputs("[now-playing] helper ended (\(ended.terminationStatus))\n", stderr)
        publish(nil)
        guard running, isEnabled else { return }
        quickFailures = Date().timeIntervalSince(launchedAt) < Self.quickFailure ? quickFailures + 1 : 0
        guard quickFailures < Self.maxQuickFailures else {
            fputs("[now-playing] giving up: Now Playing doesn't work on this Mac\n", stderr)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restartDelay) { [weak self] in
            guard let self = self, self.running, self.isEnabled else { return }
            self.launchHelper()
        }
    }

    private func received(_ data: Data) {
        guard process != nil, !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let update = NowPlayingInfo.parse(line: line, receivedAt: Date()) { apply(update) }
        }
    }

    private func apply(_ update: NowPlayingUpdate) {
        switch update {
        case .track(let bundleID, var track) where !nativeBundleIDs.contains(bundleID):
            // The artwork only comes when it changes: keep it for the same track.
            if track.artworkData == nil, let current = nowPlaying, current.trackID == track.trackID {
                track.artworkData = current.artworkData
            }
            if bundleID != self.bundleID {
                self.bundleID = bundleID
                playerName = Self.appName(bundleID)
            }
            nowPlaying = track
            publish(track)
        default:
            bundleID = nil
            nowPlaying = nil
            publish(nil)
        }
    }

    private func send(_ command: String) {
        guard let input = input else { return }
        do {
            try input.write(contentsOf: Data((command + "\n").utf8))
        } catch {
            fputs("[now-playing] command not sent: \(error.localizedDescription)\n", stderr)
        }
    }

    // Never "not running": with nothing to show, the notch says "Nothing playing".
    private func publish(_ track: NowPlaying?) {
        onChange?(.ready, track)
    }

    private static func appName(_ bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
    }
}
