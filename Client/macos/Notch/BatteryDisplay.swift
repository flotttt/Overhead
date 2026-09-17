import Foundation

// The headphones' battery as the closed notch shows it. Pure, tested in LogicTests.
enum BatteryDisplay {
    enum Tone: Equatable {
        case normal
        case low       // 20 % or less
        case critical  // 10 % or less
        case charging
    }

    // True-wireless earbuds show the lower side, the one that runs out first. nil when nothing is known yet
    // (levels are -1 until read).
    static func level(single: Int, dual: Bool, left: Int, right: Int) -> Int? {
        let known = (dual ? [left, right] : [single]).filter { $0 >= 0 }
        return known.min().map { min(100, $0) }
    }

    static func tone(level: Int, charging: Bool) -> Tone {
        if charging { return .charging }
        if level <= 10 { return .critical }
        if level <= 20 { return .low }
        return .normal
    }
}
