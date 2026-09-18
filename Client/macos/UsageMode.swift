import Foundation

// How SonyNotch is used, chosen in the setup window. Pure, tested in LogicTests.
enum UsageMode: String, CaseIterable {
    case notchOnly       // the notch and the music players, nothing about headphones (Bluetooth is never used)
    case headphonesOnly  // the headphones menu, no notch (no music player is ever read)
    case both

    // Missing (installs from before the choice existed) or unknown: everything, as before.
    init(stored: String?) {
        self = stored.flatMap(UsageMode.init(rawValue:)) ?? .both
    }

    var usesNotch: Bool { self != .headphonesOnly }
    var usesHeadphones: Bool { self != .notchOnly }
}
