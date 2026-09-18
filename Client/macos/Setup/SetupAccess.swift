import Foundation

// A permission as the setup assistant shows it. Pure, tested in LogicTests.
enum SetupAccess: Equatable {
    case granted
    case notDetermined  // macOS will ask
    case denied         // refused (or restricted): only System Settings can change it
    case unavailable    // can't tell yet (Spotify closed, for example)

    // AEDeterminePermissionToAutomateTarget's answer about Spotify.
    static func spotify(status: Int) -> SetupAccess {
        switch status {
        case 0: return .granted
        case -1744: return .notDetermined  // errAEEventWouldRequireUserConsent
        case -1743: return .denied         // errAEEventNotPermitted
        default: return .unavailable       // -600 procNotFound: Spotify isn't running
        }
    }

    // CBManager.authorization's raw value: 0 not determined, 1 restricted, 2 denied, 3 allowed always.
    static func bluetooth(rawAuthorization: Int) -> SetupAccess {
        switch rawAuthorization {
        case 3: return .granted
        case 0: return .notDetermined
        default: return .denied
        }
    }
}
