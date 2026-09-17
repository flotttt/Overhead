import Foundation

// Result of decoding what the local Spotify app reports.
enum SpotifyState: Equatable {
    case stopped            // Spotify is open with nothing loaded
    case track(NowPlaying)
    case incomplete         // not enough information: read the state through Apple Events instead
}

// Decodes the local Spotify app's signal and Apple Events replies (spec §6.1). Pure, tested in LogicTests.
enum SpotifyPlaybackInfo {
    static let localCapabilities = MusicCapabilities(canSeek: true, canSetVolume: true, canChangeDevice: false)
    static let fieldSeparator: Character = "\u{1F}"

    // com.spotify.client.PlaybackStateChanged userInfo: "Player State" (Playing / Paused / Stopped), "Track ID",
    // "Name", "Artist", "Album", "Duration" (ms), "Playback Position" (s). It never carries artwork or volume.
    static func parse(signal userInfo: [AnyHashable: Any]?, at date: Date) -> SpotifyState {
        guard let info = userInfo, let state = info["Player State"] as? String else { return .incomplete }
        if state == "Stopped" { return .stopped }
        guard state == "Playing" || state == "Paused",
              let trackID = info["Track ID"] as? String, !trackID.isEmpty else { return .incomplete }
        return .track(NowPlaying(
            trackID: trackID,
            title: info["Name"] as? String ?? "",
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            artworkURL: nil,
            duration: ((info["Duration"] as? NSNumber)?.doubleValue ?? 0) / 1000,
            position: (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0,
            positionDate: date,
            isPlaying: state == "Playing",
            volume: nil,
            deviceName: nil,
            capabilities: localCapabilities))
    }

    // SpotifyScript.readState's reply: "stopped", or 9 fields separated by U+001F — state, track id, name,
    // artist, album, duration (ms), position (ms), artwork URL, volume.
    static func parse(scriptResult text: String, at date: Date) -> SpotifyState {
        if text == "stopped" { return .stopped }
        let fields = text.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 9, fields[0] == "playing" || fields[0] == "paused", !fields[1].isEmpty else {
            return .incomplete
        }
        return .track(NowPlaying(
            trackID: fields[1],
            title: fields[2],
            artist: fields[3],
            album: fields[4],
            artworkURL: URL(string: fields[7]),
            duration: (Double(fields[5]) ?? 0) / 1000,
            position: (Double(fields[6]) ?? 0) / 1000,
            positionDate: date,
            isPlaying: fields[0] == "playing",
            volume: Int(fields[8]).map { min(100, max(0, $0)) },
            deviceName: nil,
            capabilities: localCapabilities))
    }
}
