import Foundation

// One line from NowPlayingHelper, decoded.
enum NowPlayingUpdate: Equatable {
    case nothing                                 // nothing in macOS's Now Playing
    case track(bundleID: String, NowPlaying)     // artworkData set only when the line carried a new artwork
}

// Decodes NowPlayingHelper's JSON lines (the format is described at the top of NowPlayingHelper.m).
// Pure, tested in LogicTests.
enum NowPlayingInfo {
    // Now Playing has no volume; seeking works when the track has a duration.
    static func capabilities(duration: TimeInterval) -> MusicCapabilities {
        MusicCapabilities(canSeek: duration > 0, canSetVolume: false, canChangeDevice: false)
    }

    // nil for a line that isn't one of the helper's (ignored).
    static func parse(line: String, receivedAt date: Date) -> NowPlayingUpdate? {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard let bundleID = object["bundle"] as? String, !bundleID.isEmpty,
              let title = object["title"] as? String, !title.isEmpty else { return .nothing }
        let artist = object["artist"] as? String ?? ""
        let duration = max(0, object["duration"] as? Double ?? 0)
        let timestamp = (object["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? date
        return .track(bundleID: bundleID, NowPlaying(
            // Stable per track (not per line), so the notch only flips the artwork on a real track change.
            trackID: "now-playing:\(bundleID):\(title)\u{1F}\(artist)",
            title: title,
            artist: artist,
            album: object["album"] as? String ?? "",
            artworkURL: nil,
            artworkData: (object["artwork"] as? String).flatMap { Data(base64Encoded: $0) },
            duration: duration,
            position: max(0, object["elapsed"] as? Double ?? 0),
            // A timestamp from the future (clock skew) would freeze the progress bar: never later than now.
            positionDate: min(timestamp, date),
            isPlaying: object["playing"] as? Bool ?? false,
            volume: nil,
            deviceName: nil,
            capabilities: capabilities(duration: duration)))
    }
}
