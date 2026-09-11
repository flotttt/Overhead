import Foundation

// What the notch shows while resting (spec §4.1) and which tab it opens on. Pure logic, tested in LogicTests.
enum NotchRestingState: Equatable {
    case musicAndHeadphones  // 1: artwork left, headphones mode right
    case musicOnly           // 2: artwork left, level bars right
    case headphonesOnly      // 3: headphones glyph left, mode right
    case empty               // 4: bare notch (hidden on a screen without a notch)
}

enum NotchTab: Equatable {
    case music, headphones
}

enum NotchContent {
    static let openDelay: TimeInterval = 0.15  // hover time before opening
    static let closeDelay: TimeInterval = 0.4  // time after the pointer leaves before closing

    static func restingState(hasMusic: Bool, headphonesConnected: Bool) -> NotchRestingState {
        switch (hasMusic, headphonesConnected) {
        case (true, true): return .musicAndHeadphones
        case (true, false): return .musicOnly
        case (false, true): return .headphonesOnly
        case (false, false): return .empty
        }
    }

    // The first opening of the session follows the music; afterwards the last tab the user picked wins.
    static func tabOnOpen(lastChosen: NotchTab?, hasMusic: Bool) -> NotchTab {
        lastChosen ?? (hasMusic ? .music : .headphones)
    }
}
