import Foundation

enum MusicSourceStatus: Equatable {
    case notRunning        // the player app isn't open
    case permissionDenied  // macOS refused SonyBridge the right to control it
    case ready
}

// Where the music comes from (spec §5.1). Step 1: SpotifyLocalSource; step 2 adds the Spotify Web API.
// Called on the main thread; onChange is called on the main thread.
protocol MusicSource: AnyObject {
    var onChange: ((MusicSourceStatus, NowPlaying?) -> Void)? { get set }
    func start()
    func stop()
    func refresh()
    func playPause()
    func next()
    func previous()
    func seek(to seconds: TimeInterval)
    func setVolume(_ volume: Int)
    func launchPlayer()
}
