import AppKit
import Combine

// The music state the notch shows. Follows several players at once (Spotify, Music, others) and shows the one that
// plays, the last to start when several do (MusicSourcePicker); commands go to that one.
final class MusicController: ObservableObject {
    static let openRefreshInterval: TimeInterval = 5  // re-read while the notch is open (volume isn't signalled)
    private static let artworkCacheSize = 8

    @Published private(set) var status: MusicSourceStatus = .notRunning
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var playerName: String   // the player the notch follows, for its messages
    @Published private(set) var artwork: NSImage? {
        didSet { artworkTint = artwork.flatMap(Self.tint(of:)) }
    }
    @Published private(set) var artworkTint: NSColor?  // vivid average colour of the artwork

    // The last previous / next asked from SonyNotch, so the artwork can flip the matching way.
    private(set) var lastSkip: (backward: Bool, date: Date)?

    // Something to show: a track, playing or paused (even without the right to control it).
    var hasMusic: Bool { status != .notRunning && nowPlaying != nil }

    private let sources: [MusicSource]
    private var states: [String: (status: MusicSourceStatus, track: NowPlaying?)] = [:]
    private var playingSince: [String: Date] = [:]
    private var activeID: String
    private var running = false
    private var refreshTimer: Timer?
    private var seekThrottle = SendThrottle()
    private var volumeThrottle = SendThrottle()
    private var artworkCache: [String: NSImage] = [:]  // by artwork URL, or "track:<id>" for image data
    private var artworkOrder: [String] = []
    private var artworkRequest: URL?
    private var lastLogLine = ""

    init(sources: [MusicSource] = ScriptedPlayer.all.map(ScriptedPlayerSource.init(player:)) + [NowPlayingSource()]) {
        self.sources = sources
        activeID = sources.first?.id ?? ""
        playerName = sources.first?.playerName ?? ""
        for source in sources {
            source.onChange = { [weak self, weak source] status, track in
                guard let source = source else { return }
                self?.apply(source, status, track)
            }
        }
    }

    private var active: MusicSource? { sources.first { $0.id == activeID } }

    // Options › Other Players: Deezer, YouTube Music, browsers… through macOS's Now Playing.
    func setOtherPlayers(_ on: Bool) {
        sources.compactMap { $0 as? NowPlayingSource }.forEach { $0.isEnabled = on }
    }

    func start() {
        guard !running else { return }
        running = true
        sources.forEach { $0.start() }
    }

    // "Show Notch" off (or headphones-only mode): no player reads at all.
    func stop() {
        guard running else { return }
        running = false
        notchDidClose()
        sources.forEach { $0.stop() }
        states = [:]
        playingSince = [:]
        status = .notRunning
        nowPlaying = nil
        artwork = nil
        artworkRequest = nil
        log("stopped")
    }

    // Read the players again now (after the setup window got a permission, for example).
    func refresh() {
        guard running else { return }
        sources.forEach { $0.refresh() }
    }

    // Opening reads once (which also retries a refused permission), then every 5 s while open.
    func notchDidOpen() {
        guard running else { return }
        refresh()
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.openRefreshInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.status == .ready else { return }
            self.active?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func notchDidClose() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func playPause() { active?.playPause() }

    func next() {
        lastSkip = (false, Date())
        active?.next()
    }

    func previous() {
        lastSkip = (true, Date())
        active?.previous()
    }

    // True when the current track change follows a "previous" asked within the last few seconds.
    var trackChangeIsBackward: Bool {
        guard let skip = lastSkip else { return false }
        return skip.backward && Date().timeIntervalSince(skip.date) < 3
    }

    // Sliders: at most one command per 150 ms while dragging, the final value always, then a read-back.
    func seek(to seconds: TimeInterval, final: Bool) {
        if seekThrottle.shouldSend(final: final) { active?.seek(to: seconds) }
        if final { active?.refresh() }
    }

    func setVolume(_ volume: Int, final: Bool) {
        if volumeThrottle.shouldSend(final: final) { active?.setVolume(volume) }
        if final { active?.refresh() }
    }

    func launchPlayer() { active?.launchPlayer() }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    private func apply(_ source: MusicSource, _ newStatus: MusicSourceStatus, _ track: NowPlaying?) {
        guard running else { return }
        let wasPlaying = states[source.id]?.track?.isPlaying == true
        states[source.id] = (newStatus, track)
        let playing = newStatus != .notRunning && track?.isPlaying == true
        if playing && !wasPlaying { playingSince[source.id] = Date() }
        if !playing { playingSince[source.id] = nil }

        let snapshots = sources.map { source -> SourceSnapshot in
            let state = states[source.id]
            let running = state.map { $0.status != .notRunning } ?? false
            return SourceSnapshot(id: source.id, isPlaying: running && state?.track?.isPlaying == true,
                                  hasTrack: running && state?.track != nil)
        }
        activeID = MusicSourcePicker.pick(snapshots, playingSince: playingSince, current: activeID) ?? activeID
        showActive()
    }

    private func showActive() {
        let state = states[activeID] ?? (.notRunning, nil)
        status = state.status
        nowPlaying = state.track
        playerName = active?.playerName ?? ""
        loadArtwork(for: state.track)
        let name = activeID
        switch (state.status, state.track) {
        case (.notRunning, _): log("\(name) not running")
        case (.permissionDenied, _): log("\(name) permission denied")
        case (.ready, nil): log("\(name) nothing playing")
        case (.ready, let track?):
            log("\(name) \(track.isPlaying ? "playing" : "paused") \(track.trackID) vol \(track.volume.map(String.init) ?? "?")")
        }
    }

    // One line per actual change (the 5 s re-reads stay quiet).
    private func log(_ line: String) {
        guard line != lastLogLine else { return }
        lastLogLine = line
        fputs("[music] \(line)\n", stderr)
    }

    private func loadArtwork(for track: NowPlaying?) {
        if let track = track, let data = track.artworkData {
            let key = "track:" + track.trackID
            artworkRequest = nil
            if let cached = artworkCache[key] {
                artwork = cached
            } else if let image = NSImage(data: data) {
                remember(image, for: key)
                artwork = image
            }
            return
        }
        guard let url = track?.artworkURL else {
            // Now Playing only sends a track's artwork once: coming back to it, reuse the one already shown.
            artwork = track.flatMap { artworkCache["track:" + $0.trackID] }
            artworkRequest = nil
            return
        }
        if let cached = artworkCache[url.absoluteString] {
            artwork = cached
            artworkRequest = nil
            return
        }
        guard artworkRequest != url else { return }  // already downloading
        artworkRequest = url
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async {
                guard let self = self, self.artworkRequest == url else { return }
                self.artworkRequest = nil
                guard let image = image else { return }
                self.remember(image, for: url.absoluteString)
                self.artwork = image
            }
        }.resume()
    }

    // The artwork's average colour, pushed bright and saturated enough to read on black.
    private static func tint(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = data.assumingMemoryBound(to: UInt8.self)
        let average = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        // A grey artwork has no meaningful hue (it would come out red): keep it light grey.
        guard average.saturationComponent >= 0.12 else { return NSColor(white: 0.85, alpha: 1) }
        return NSColor(hue: average.hueComponent, saturation: max(average.saturationComponent, 0.55),
                       brightness: max(average.brightnessComponent, 0.85), alpha: 1)
    }

    private func remember(_ image: NSImage, for key: String) {
        artworkCache[key] = image
        artworkOrder.removeAll { $0 == key }
        artworkOrder.append(key)
        if artworkOrder.count > Self.artworkCacheSize {
            artworkCache[artworkOrder.removeFirst()] = nil
        }
    }
}
