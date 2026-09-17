import Foundation

// AppleScript sent to the local Spotify app. Only ever run on SpotifyLocalSource's script queue.
enum SpotifyScript {
    enum Result: Equatable {
        case success(String)
        case failure(Int)  // AppleScript / Apple Event error number
    }

    // Fields joined by U+001F; times as integer milliseconds so no locale decimal separator shows up.
    // Parsed by SpotifyPlaybackInfo.parse(scriptResult:at:).
    static let readState = """
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
        """

    // One command, e.g. "playpause", "next track", "set sound volume to 40".
    static func command(_ body: String) -> String {
        """
        with timeout of 2 seconds
            tell application id "com.spotify.client" to \(body)
        end timeout
        """
    }

    static func run(_ script: NSAppleScript?) -> Result {
        guard let script = script else { return .failure(-2700) }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error = error {
            return .failure((error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -2700)
        }
        return .success(output.stringValue ?? "")
    }
}
