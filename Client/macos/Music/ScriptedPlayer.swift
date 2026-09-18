import Foundation

// A music app SonyNotch drives with AppleScript: how to read it, command it and decode it.
struct ScriptedPlayer {
    let id: String                  // log prefix and source identity
    let name: String                // shown in the notch ("Spotify isn't open")
    let bundleIdentifier: String
    let downloadURL: URL?           // where to get it when it isn't installed
    let signalName: Notification.Name
    let readScript: String          // fields joined by U+001F, times as integer milliseconds (no locale separator)
    let artworkScript: String?      // returns the artwork's raw data; nil when readScript already gives a URL
    let parseSignal: ([AnyHashable: Any]?, Date) -> PlayerState
    let parseRead: (String, Date) -> PlayerState

    static let spotify = ScriptedPlayer(
        id: "spotify",
        name: "Spotify",
        bundleIdentifier: "com.spotify.client",
        downloadURL: URL(string: "https://www.spotify.com/download/mac/"),
        signalName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
        readScript: """
            with timeout of 2 seconds
                tell application id "com.spotify.client"
                    set playerState to (player state as text)
                    if playerState is "stopped" then return "stopped"
                    set t to current track
                    set sep to (character id 31)
                    set art to artwork url of t
                    if art is missing value then set art to ""
                    return playerState & sep & (id of t) & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as text) & sep & ((((player position) * 1000) div 1) as text) & sep & art & sep & ((sound volume) as text)
                end tell
            end timeout
            """,
        artworkScript: nil,
        parseSignal: SpotifyPlaybackInfo.parse(signal:at:),
        parseRead: SpotifyPlaybackInfo.parse(scriptResult:at:))

    // The players the notch follows, in this order when none plays.
    static let all: [ScriptedPlayer] = [.spotify, .appleMusic]

    static let appleMusic = ScriptedPlayer(
        id: "music",
        name: tr("Music"),
        bundleIdentifier: "com.apple.Music",
        downloadURL: nil,  // part of macOS
        signalName: Notification.Name("com.apple.Music.playerInfo"),
        readScript: """
            with timeout of 2 seconds
                tell application id "com.apple.Music"
                    set playerState to (player state as text)
                    if playerState is "stopped" then return "stopped"
                    set t to current track
                    set sep to (character id 31)
                    set d to duration of t
                    if d is missing value then set d to 0  -- radio and other streams
                    return playerState & sep & (persistent ID of t) & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (((d * 1000) div 1) as text) & sep & ((((player position) * 1000) div 1) as text) & sep & ((sound volume) as text)
                end tell
            end timeout
            """,
        artworkScript: """
            with timeout of 3 seconds
                tell application id "com.apple.Music"
                    if (count of artworks of current track) is 0 then return ""
                    return raw data of artwork 1 of current track
                end tell
            end timeout
            """,
        parseSignal: AppleMusicPlaybackInfo.parse(signal:at:),
        parseRead: AppleMusicPlaybackInfo.parse(scriptResult:at:))
}
