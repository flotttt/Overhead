import Foundation

// Decodes the Music app's replies. Pure, tested in LogicTests.
enum AppleMusicPlaybackInfo {
    static let capabilities = MusicCapabilities(canSeek: true, canSetVolume: true, canChangeDevice: false)

    // com.apple.Music.playerInfo carries no position: apart from "Stopped", it only says it's time to read.
    static func parse(signal userInfo: [AnyHashable: Any]?, at date: Date) -> PlayerState {
        (userInfo?["Player State"] as? String) == "Stopped" ? .stopped : .incomplete
    }

    // AppleMusicScript.readState's reply: "stopped", or 8 fields separated by U+001F — state, persistent ID, name,
    // artist, album, duration (ms), position (ms), volume. The artwork is read on its own (it's image data).
    static func parse(scriptResult text: String, at date: Date) -> PlayerState {
        if text == "stopped" { return .stopped }
        let fields = text.split(separator: SpotifyPlaybackInfo.fieldSeparator, omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count == 8, fields[0] == "playing" || fields[0] == "paused", !fields[1].isEmpty else {
            return .incomplete
        }
        return .track(NowPlaying(
            trackID: "apple-music:" + fields[1],
            title: fields[2],
            artist: fields[3],
            album: fields[4],
            artworkURL: nil,
            duration: (Double(fields[5]) ?? 0) / 1000,
            position: (Double(fields[6]) ?? 0) / 1000,
            positionDate: date,
            isPlaying: fields[0] == "playing",
            volume: Int(fields[7]).map { min(100, max(0, $0)) },
            deviceName: nil,
            capabilities: capabilities))
    }
}
