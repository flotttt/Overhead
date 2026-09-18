import Foundation

// Runs AppleScript for a ScriptedPlayerSource. Only ever on that source's script queue.
enum PlayerScript {
    enum Result: Equatable {
        case success(String)
        case failure(Int)  // AppleScript / Apple Event error number
    }

    // One command for a player, e.g. "playpause", "next track", "set sound volume to 40".
    static func command(_ body: String, app bundleIdentifier: String) -> String {
        """
        with timeout of 2 seconds
            tell application id "\(bundleIdentifier)" to \(body)
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

    // For a script that returns raw data (artwork): nil on failure or an empty reply.
    static func runData(_ script: NSAppleScript?) -> Data? {
        guard let script = script else { return nil }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        guard error == nil, !output.data.isEmpty, output.descriptorType != typeUnicodeText else { return nil }
        return output.data
    }
}
