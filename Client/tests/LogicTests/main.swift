import Foundation
import CoreGraphics

// Minimal test runner (XCTest isn't available without Xcode). Exit code 1 on any failure.
var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

// ReconnectPolicy: 3 s, 10 s, 30 s, then every 60 s; reset restarts.
do {
    var policy = ReconnectPolicy()
    let delays = (0..<6).map { _ in policy.nextDelay() }
    check(delays == [3, 10, 30, 60, 60, 60], "reconnect schedule was \(delays)")
    policy.reset()
    check(policy.nextDelay() == 3, "reset restarts the schedule")
}

// PollGuard: a poll is ignored for 3 s after the user changed that setting.
do {
    var pollGuard = PollGuard<String>(window: 3)
    let t0 = Date(timeIntervalSince1970: 1_000)
    check(pollGuard.shouldAcceptPoll(for: "ambient", at: t0), "no user change: accept")
    pollGuard.userChanged("ambient", at: t0)
    check(!pollGuard.shouldAcceptPoll(for: "ambient", at: t0.addingTimeInterval(2.9)), "inside the window: reject")
    check(pollGuard.shouldAcceptPoll(for: "ambient", at: t0.addingTimeInterval(3)), "after the window: accept")
    check(pollGuard.shouldAcceptPoll(for: "eq", at: t0.addingTimeInterval(1)), "other keys are unaffected")
}

// SendThrottle: at most one send per 150 ms while dragging; the final value always goes out.
do {
    var throttle = SendThrottle(interval: 0.15)
    let t0 = Date(timeIntervalSince1970: 1_000)
    check(throttle.shouldSend(at: t0, final: false), "first drag event sends")
    check(!throttle.shouldSend(at: t0.addingTimeInterval(0.10), final: false), "too soon: skip")
    check(throttle.shouldSend(at: t0.addingTimeInterval(0.16), final: false), "after the interval: send")
    check(throttle.shouldSend(at: t0.addingTimeInterval(0.17), final: true), "final value always sends")
}

// NotchGeometry: a 14" MacBook Pro screen (1512 × 982 pt, notch 188 pt wide, 32 pt high).
do {
    let screen = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                               auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 662, height: 32),
                               auxiliaryTopRight: CGRect(x: 850, y: 950, width: 662, height: 32),
                               menuBarHeight: 32)
    let geometry = NotchGeometry(screen: screen)
    check(geometry.hasNotch, "notched screen detected")
    check(geometry.notch == CGRect(x: 662, y: 950, width: 188, height: 32), "notch rect was \(geometry.notch)")
    check(geometry.extended == CGRect(x: 626, y: 950, width: 260, height: 32), "extended rect was \(geometry.extended)")
    check(geometry.open == CGRect(x: 566, y: 792, width: 380, height: 190), "open rect was \(geometry.open)")
    check(geometry.restingFrame(for: .empty) == geometry.notch, "empty state: bare notch")
    check(geometry.restingFrame(for: .musicOnly) == geometry.extended, "music: extended notch")
}

// NotchGeometry: an external screen without a notch, right of the primary screen.
do {
    let frame = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    let geometry = NotchGeometry(screen: ScreenMetrics(frame: frame, safeAreaTop: 0, auxiliaryTopLeft: nil,
                                                       auxiliaryTopRight: nil, menuBarHeight: 25))
    check(!geometry.hasNotch, "no notch")
    check(geometry.notch == CGRect(x: 2697, y: 1415, width: 190, height: 25), "simulated pill was \(geometry.notch)")
    check(geometry.restingFrame(for: .empty) == nil, "empty state hides the pill")
    check(geometry.restingFrame(for: .headphonesOnly) == geometry.extended, "headphones: extended pill")

    let autoHidden = NotchGeometry(screen: ScreenMetrics(frame: frame, safeAreaTop: 0, auxiliaryTopLeft: nil,
                                                         auxiliaryTopRight: nil, menuBarHeight: 0))
    check(autoHidden.notch.height == 24, "auto-hidden menu bar: fallback pill height")
    let partial = NotchGeometry(screen: ScreenMetrics(frame: frame, safeAreaTop: 32, auxiliaryTopLeft: nil,
                                                      auxiliaryTopRight: nil, menuBarHeight: 32))
    check(!partial.hasNotch, "safe area without auxiliary areas: no notch")
}

// NotchContent: resting state (spec §4.1), tab on opening, hover delays.
do {
    check(NotchContent.restingState(hasMusic: true, headphonesConnected: true) == .musicAndHeadphones, "state 1")
    check(NotchContent.restingState(hasMusic: true, headphonesConnected: false) == .musicOnly, "state 2")
    check(NotchContent.restingState(hasMusic: false, headphonesConnected: true) == .headphonesOnly, "state 3")
    check(NotchContent.restingState(hasMusic: false, headphonesConnected: false) == .empty, "state 4")
    check(NotchContent.tabOnOpen(lastChosen: nil, hasMusic: true) == .music, "first open with music: Music")
    check(NotchContent.tabOnOpen(lastChosen: nil, hasMusic: false) == .headphones, "first open without music: Headphones")
    check(NotchContent.tabOnOpen(lastChosen: .headphones, hasMusic: true) == .headphones, "then the last chosen tab")
    check(NotchContent.openDelay == 0.15 && NotchContent.closeDelay == 0.4, "hover delays")
}

if failures > 0 {
    print("LogicTests: \(failures) failure(s)")
    exit(1)
}
print("LogicTests: all passed")
