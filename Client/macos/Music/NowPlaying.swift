import Foundation

// What a music source can do with the current track (the Web source of step 2 depends on the device).
struct MusicCapabilities: Equatable {
    var canSeek: Bool
    var canSetVolume: Bool
    var canChangeDevice: Bool
}

// The track a music source is playing (or paused on). `position` was true at `positionDate`; PlaybackClock
// derives the live position from it, so nothing polls while a track plays.
struct NowPlaying: Equatable {
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var artworkData: Data? = nil  // image bytes, for players that give the artwork itself (Music)
    var duration: TimeInterval   // seconds; 0 when unknown
    var position: TimeInterval   // seconds, at positionDate
    var positionDate: Date
    var isPlaying: Bool
    var volume: Int?             // 0...100; nil until known
    var deviceName: String?      // nil = this Mac
    var capabilities: MusicCapabilities
}
