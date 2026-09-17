import AppKit
import Combine

// The music state the notch shows, from the active MusicSource (spec §5.1). Step 1: the local Spotify app.
final class MusicController: ObservableObject {
    static let openRefreshInterval: TimeInterval = 5  // re-read while the notch is open (volume isn't signalled)
    private static let artworkCacheSize = 8

    @Published private(set) var status: MusicSourceStatus = .notRunning
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?

    // Something to show: a track, playing or paused (even without the right to control it).
    var hasMusic: Bool { status != .notRunning && nowPlaying != nil }

    private let source: MusicSource
    private var running = false
    private var refreshTimer: Timer?
    private var seekThrottle = SendThrottle()
    private var volumeThrottle = SendThrottle()
    private var artworkCache: [URL: NSImage] = [:]
    private var artworkOrder: [URL] = []
    private var artworkRequest: URL?
    private var lastLogLine = ""

    init(source: MusicSource = SpotifyLocalSource()) {
        self.source = source
        source.onChange = { [weak self] status, track in self?.apply(status, track) }
    }

    func start() {
        guard !running else { return }
        running = true
        source.start()
    }

    // "Show Notch" off: no Spotify reads at all (spec §4.3).
    func stop() {
        guard running else { return }
        running = false
        notchDidClose()
        source.stop()
        status = .notRunning
        nowPlaying = nil
        artwork = nil
        artworkRequest = nil
        log("stopped")
    }

    // Opening reads once (which also retries a refused permission, spec §6.3), then every 5 s while open.
    func notchDidOpen() {
        guard running else { return }
        source.refresh()
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.openRefreshInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.status == .ready else { return }
            self.source.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func notchDidClose() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func playPause() { source.playPause() }

    func next() { source.next() }

    func previous() { source.previous() }

    // Sliders: at most one command per 150 ms while dragging, the final value always, then a read-back.
    func seek(to seconds: TimeInterval, final: Bool) {
        if seekThrottle.shouldSend(final: final) { source.seek(to: seconds) }
        if final { source.refresh() }
    }

    func setVolume(_ volume: Int, final: Bool) {
        if volumeThrottle.shouldSend(final: final) { source.setVolume(volume) }
        if final { source.refresh() }
    }

    func launchPlayer() { source.launchPlayer() }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    private func apply(_ newStatus: MusicSourceStatus, _ track: NowPlaying?) {
        guard running else { return }
        status = newStatus
        nowPlaying = track
        loadArtwork(track?.artworkURL)
        switch (newStatus, track) {
        case (.notRunning, _): log("not running")
        case (.permissionDenied, _): log("permission denied")
        case (.ready, nil): log("nothing playing")
        case (.ready, let track?):
            log("\(track.isPlaying ? "playing" : "paused") \(track.trackID) vol \(track.volume.map(String.init) ?? "?")")
        }
    }

    // One line per actual change (the 5 s re-reads stay quiet).
    private func log(_ line: String) {
        guard line != lastLogLine else { return }
        lastLogLine = line
        fputs("[spotify] \(line)\n", stderr)
    }

    private func loadArtwork(_ url: URL?) {
        guard let url = url else {
            artwork = nil
            artworkRequest = nil
            return
        }
        if let cached = artworkCache[url] {
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
                self.remember(image, for: url)
                self.artwork = image
            }
        }.resume()
    }

    private func remember(_ image: NSImage, for url: URL) {
        artworkCache[url] = image
        artworkOrder.removeAll { $0 == url }
        artworkOrder.append(url)
        if artworkOrder.count > Self.artworkCacheSize {
            artworkCache[artworkOrder.removeFirst()] = nil
        }
    }
}
