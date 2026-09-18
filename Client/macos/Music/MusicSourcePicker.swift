import Foundation

// A music source's state as the picker needs it.
struct SourceSnapshot: Equatable {
    var id: String
    var isPlaying: Bool
    var hasTrack: Bool
}

// Which player the notch follows, automatically. Pure, tested in LogicTests.
enum MusicSourcePicker {
    // The one playing (the last to start when several play); else the current one while it still has a track;
    // else any that has one; else the current (or first) one, for its "not open" message.
    static func pick(_ sources: [SourceSnapshot], playingSince: [String: Date], current: String?) -> String? {
        let playing = sources.filter(\.isPlaying)
        if let latest = playing.max(by: { (playingSince[$0.id] ?? .distantPast) < (playingSince[$1.id] ?? .distantPast) }) {
            return latest.id
        }
        if let current = current, sources.contains(where: { $0.id == current && $0.hasTrack }) { return current }
        if let withTrack = sources.first(where: \.hasTrack) { return withTrack.id }
        return current ?? sources.first?.id
    }
}
