import Foundation

enum MusicSourceStatus: Equatable {
    case notRunning        // the player app isn't open
    case permissionDenied  // macOS refused SonyNotch the right to control it
    case ready
}

// One music app. ScriptedPlayerSource covers Spotify and Music; the Spotify Web API would be another.
// Called on the main thread; onChange is called on the main thread.
protocol MusicSource: AnyObject {
    var id: String { get }
    var playerName: String { get }
    var bundleIdentifier: String { get }
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
