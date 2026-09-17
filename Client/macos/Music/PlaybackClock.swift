import Foundation

// Live playback position and its display, from the last known position.
enum PlaybackClock {
    static func position(of track: NowPlaying, at date: Date) -> TimeInterval {
        var position = track.position
        if track.isPlaying { position += date.timeIntervalSince(track.positionDate) }
        if track.duration > 0 { position = min(position, track.duration) }
        return max(0, position)
    }

    // 0...1 through the track; 0 when its length isn't known.
    static func progress(of track: NowPlaying, at date: Date) -> Double {
        guard track.duration > 0 else { return 0 }
        return min(1, position(of: track, at: date) / track.duration)
    }

    // "1:05", "12:34", "1:02:03".
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
