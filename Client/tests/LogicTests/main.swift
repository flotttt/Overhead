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
    check(geometry.open == CGRect(x: 606, y: 816, width: 300, height: 166), "open rect was \(geometry.open)")
    check(geometry.restingFrame(for: .empty) == geometry.notch, "empty state: bare notch")
    check(geometry.restingFrame(for: .musicOnly) == geometry.extended, "music: extended notch")
    check(geometry.restingTrailingZone == CGRect(x: 850, y: 950, width: 36, height: 32),
          "resting trailing zone was \(geometry.restingTrailingZone)")
}

// NotchLayout: user sizes are clamped; the zoom never lays the open content out smaller than it needs.
do {
    let clamped = NotchLayout(openSize: CGSize(width: 100, height: 1000), sideExtension: 5, zoom: 3)
    check(clamped.openSize == CGSize(width: 280, height: 260), "open size clamped, was \(clamped.openSize)")
    check(clamped.sideExtension == 28 && clamped.zoom == 1.3, "side and zoom clamped")
    check(clamped.contentScale == 1, "zoom limited by the width, was \(clamped.contentScale)")
    let roomy = NotchLayout(openSize: CGSize(width: 400, height: 240), sideExtension: 60, zoom: 1.2)
    check(roomy.contentScale == 1.2 && roomy.restingScale == 1.2, "zoom applied when the notch is large enough")
    let narrowSides = NotchLayout(openSize: NotchLayout.default.openSize, sideExtension: 30, zoom: 1.3)
    check(narrowSides.restingScale == 1, "resting icons limited by the side width, was \(narrowSides.restingScale)")
    check(NotchLayout.default.contentScale == 1 && NotchLayout.default.restingScale == 1, "default: no zoom")
    check(NotchLayout.default.restingArtworkSize(notchHeight: 32) == 24, "default resting artwork")
    let bigArtwork = NotchLayout(openSize: NotchLayout.default.openSize, sideExtension: 36, zoom: 1, restingArtwork: 40)
    check(bigArtwork.restingArtwork == 30, "resting artwork clamped, was \(bigArtwork.restingArtwork)")
    check(bigArtwork.restingArtworkSize(notchHeight: 32) == 28, "resting artwork fits the notch height")
    let thinSides = NotchLayout(openSize: NotchLayout.default.openSize, sideExtension: 28, zoom: 1, restingArtwork: 30)
    check(thinSides.restingArtworkSize(notchHeight: 32) == 22, "resting artwork fits the side width")

    let screen = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                               auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 662, height: 32),
                               auxiliaryTopRight: CGRect(x: 850, y: 950, width: 662, height: 32),
                               menuBarHeight: 32)
    let geometry = NotchGeometry(screen: screen, layout: roomy)
    check(geometry.extended == CGRect(x: 602, y: 950, width: 308, height: 32), "custom extended was \(geometry.extended)")
    check(geometry.open == CGRect(x: 556, y: 742, width: 400, height: 240), "custom open was \(geometry.open)")
    check(geometry.restingTrailingZone == CGRect(x: 850, y: 950, width: 60, height: 32), "custom trailing zone")
}

// NotchScrollGesture: two-finger swipes skip tracks, vertical scrolling sets the volume.
do {
    func sample(_ dx: CGFloat, _ dy: CGFloat, _ phase: ScrollSample.Phase, natural: Bool = true,
                precise: Bool = true) -> ScrollSample {
        ScrollSample(deltaX: dx, deltaY: dy, precise: precise, inverted: natural, phase: phase)
    }
    // Natural scrolling: fingers moving left give a negative deltaX.
    var swipe = NotchScrollGesture()
    check(swipe.handle(sample(-10, 0, .began)) == nil, "swipe starts")
    check(swipe.handle(sample(-30, 1, .changed)) == nil, "not far enough yet")
    check(swipe.handle(sample(-30, 0, .changed)) == .previousTrack, "fingers left: previous track")
    check(swipe.handle(sample(-80, 0, .changed)) == nil, "one skip per swipe")
    check(swipe.handle(sample(0, 0, .ended)) == nil, "swipe ends")
    check(swipe.handle(sample(-5, 0, .momentum)) == nil, "momentum ignored")
    check(swipe.handle(sample(20, 0, .began)) == nil && swipe.handle(sample(50, 0, .changed)) == .nextTrack,
          "fingers right: next track")
    var classic = NotchScrollGesture()
    _ = classic.handle(sample(10, 0, .began, natural: false))
    check(classic.handle(sample(60, 0, .changed, natural: false)) == .previousTrack,
          "without natural scrolling the deltas are the other way round")

    // Vertical: 1 % per 6 pt, fingers up raise the volume (natural scrolling: negative deltaY).
    var volume = NotchScrollGesture()
    check(volume.handle(sample(0, -10, .began)) == .volume(1), "fingers up: louder")
    check(volume.handle(sample(0, -20, .changed)) == .volume(4), "remainder carried over (4 pt + 20 pt)")
    check(volume.handle(sample(30, -2, .changed)) == nil, "axis locked: sideways drift doesn't skip")
    check(volume.handle(sample(0, 12, .changed)) == .volume(-1), "fingers down: quieter (2 pt left over, 12 pt down)")
    check(volume.handle(sample(0, -30, .momentum)) == nil, "no volume from momentum")
    let defaults = NotchGesturePreferences()
    check(NotchScrollAction.nextTrack.applying(defaults) == .nextTrack && NotchScrollAction.volume(3).applying(defaults) == .volume(3),
          "default preferences keep the action")
    let reversed = NotchGesturePreferences(swipeToSkip: true, scrollForVolume: true, reverseSwipe: true, reverseScroll: true)
    check(NotchScrollAction.nextTrack.applying(reversed) == .previousTrack, "reversed swipe")
    check(NotchScrollAction.previousTrack.applying(reversed) == .nextTrack, "reversed swipe, other way")
    check(NotchScrollAction.volume(3).applying(reversed) == .volume(-3), "reversed scroll")
    let off = NotchGesturePreferences(swipeToSkip: false, scrollForVolume: false, reverseSwipe: false, reverseScroll: false)
    check(NotchScrollAction.nextTrack.applying(off) == nil && NotchScrollAction.volume(3).applying(off) == nil,
          "disabled gestures do nothing")
    check(!VolumeDetent.crossed(from: 41, to: 49) && VolumeDetent.crossed(from: 49, to: 50), "detent every 10 %")
    check(VolumeDetent.crossed(from: 52, to: 48) && !VolumeDetent.crossed(from: 50, to: 50), "detent going down")
    check(VolumeDetent.crossed(from: 3, to: 0) && VolumeDetent.crossed(from: 97, to: 100), "detents at the ends")
    var wheel = NotchScrollGesture()
    check(wheel.handle(sample(0, 1, .none, natural: false, precise: false)) == .volume(5), "mouse wheel up: +5 %")
    check(wheel.handle(sample(0, -2, .none, natural: false, precise: false)) == .volume(-5), "mouse wheel down: -5 %")
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

// NotchContent: resting state, tab on opening, hover delays.
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

// AppVersion / ReleaseInfo: is the latest GitHub release newer than this app?
do {
    check(AppVersion("1.0.0")! < AppVersion("1.0.1")!, "patch is newer")
    check(AppVersion("1.10.0")! > AppVersion("1.9.9")!, "numeric, not alphabetical")
    check(AppVersion("v1.2")! == AppVersion("1.2.0")!, "leading v and missing zeros")
    check(AppVersion("2.0.0-beta.1")! == AppVersion("2.0.0")!, "pre-release suffix ignored")
    check(AppVersion("abc") == nil && AppVersion("") == nil, "not a version")

    let json = """
        {"tag_name": "v1.1.0", "html_url": "https://github.com/flotttt/SonyNotch/releases/tag/v1.1.0",
         "draft": false, "prerelease": false, "name": "SonyNotch 1.1.0",
         "assets": [
           {"name": "SonyNotch.zip.sha256", "browser_download_url": "https://github.com/flotttt/SonyNotch/releases/download/v1.1.0/SonyNotch.zip.sha256"},
           {"name": "SonyNotch.zip", "browser_download_url": "https://github.com/flotttt/SonyNotch/releases/download/v1.1.0/SonyNotch.zip"}
         ]}
        """
    let latest = ReleaseInfo.parse(json: Data(json.utf8))
    check(latest?.version == AppVersion("1.1.0") && latest?.tag == "v1.1.0", "release parsed")
    check(latest?.pageURL == URL(string: "https://github.com/flotttt/SonyNotch/releases/tag/v1.1.0"), "release page")
    check(latest?.appZipURL == URL(string: "https://github.com/flotttt/SonyNotch/releases/download/v1.1.0/SonyNotch.zip"),
          "app zip asset")
    check(latest?.checksumURL?.lastPathComponent == "SonyNotch.zip.sha256", "checksum asset")
    let noAssets = json.replacingOccurrences(of: "SonyNotch.zip", with: "Other.zip")
    let withoutZip = ReleaseInfo.parse(json: Data(noAssets.utf8))
    check(withoutZip != nil && withoutZip?.appZipURL == nil && withoutZip?.checksumURL == nil,
          "release without the app zip: still an update, not installable")
    let hash = "46e1ca5c5edf50a61338cde32ddc2b34ed447a42afc79452cf0d3afa41a53299"
    check(ReleaseInfo.checksum(fromFile: "\(hash)  SonyNotch.zip\n") == hash, "checksum file read")
    check(ReleaseInfo.checksum(fromFile: hash.uppercased()) == hash, "checksum lowercased")
    check(ReleaseInfo.checksum(fromFile: "not a hash  SonyNotch.zip") == nil, "invalid checksum file")
    check(ReleaseInfo.update(currentVersion: "1.0.0", latest: latest) == latest, "older app: update available")
    check(ReleaseInfo.update(currentVersion: "1.1.0", latest: latest) == nil, "same version: no update")
    check(ReleaseInfo.update(currentVersion: "1.2.0", latest: latest) == nil, "newer app: no update")
    check(ReleaseInfo.update(currentVersion: "dev", latest: latest) == nil, "unknown app version: no update")
    let prerelease = json.replacingOccurrences(of: "\"prerelease\": false", with: "\"prerelease\": true")
    check(ReleaseInfo.parse(json: Data(prerelease.utf8)) == nil, "pre-releases ignored")
    check(ReleaseInfo.parse(json: Data("{}".utf8)) == nil, "malformed reply")
}

// BatteryDisplay: which level the closed notch shows, and its colour.
do {
    check(BatteryDisplay.level(single: 80, dual: false, left: -1, right: -1) == 80, "headphones: their level")
    check(BatteryDisplay.level(single: -1, dual: true, left: 70, right: 40) == 40, "earbuds: the lower one")
    check(BatteryDisplay.level(single: 90, dual: true, left: -1, right: 55) == 55, "earbuds: a missing side is ignored")
    check(BatteryDisplay.level(single: -1, dual: false, left: -1, right: -1) == nil, "unknown level")
    check(BatteryDisplay.level(single: 120, dual: false, left: -1, right: -1) == 100, "clamped to 100")
    check(BatteryDisplay.tone(level: 50, charging: false) == .normal, "normal")
    check(BatteryDisplay.tone(level: 20, charging: false) == .low && BatteryDisplay.tone(level: 10, charging: false) == .critical,
          "low at 20 %, critical at 10 %")
    check(BatteryDisplay.tone(level: 5, charging: true) == .charging, "charging wins")
}

// PlaybackClock: live position from the last known one; display format.
do {
    let t0 = Date(timeIntervalSince1970: 1_000)
    var track = NowPlaying(trackID: "spotify:track:1", title: "A", artist: "B", album: "C", artworkURL: nil,
                           duration: 200, position: 30, positionDate: t0, isPlaying: true, volume: 50,
                           deviceName: nil,
                           capabilities: MusicCapabilities(canSeek: true, canSetVolume: true, canChangeDevice: false))
    check(PlaybackClock.position(of: track, at: t0.addingTimeInterval(12)) == 42, "playing: advances")
    check(PlaybackClock.position(of: track, at: t0.addingTimeInterval(500)) == 200, "bounded by the duration")
    check(PlaybackClock.position(of: track, at: t0.addingTimeInterval(-40)) == 0, "never negative")
    track.isPlaying = false
    check(PlaybackClock.position(of: track, at: t0.addingTimeInterval(12)) == 30, "paused: frozen")
    track.isPlaying = true
    track.duration = 0
    check(PlaybackClock.position(of: track, at: t0.addingTimeInterval(500)) == 530, "unknown duration: not bounded")
    let nextTrack = NowPlaying(trackID: "spotify:track:2", title: "D", artist: "E", album: "F", artworkURL: nil,
                               duration: 180, position: 0, positionDate: t0.addingTimeInterval(100), isPlaying: true,
                               volume: 50, deviceName: nil, capabilities: track.capabilities)
    check(PlaybackClock.position(of: nextTrack, at: t0.addingTimeInterval(100)) == 0, "track change: starts from 0")
    check(PlaybackClock.progress(of: nextTrack, at: t0.addingTimeInterval(145)) == 0.25, "progress: a quarter in")
    var unknownLength = nextTrack
    unknownLength.duration = 0
    check(PlaybackClock.progress(of: unknownLength, at: t0.addingTimeInterval(145)) == 0, "progress without a duration")
    check(PlaybackClock.progress(of: nextTrack, at: t0.addingTimeInterval(1_000)) == 1, "progress capped at the end")
    check(PlaybackClock.format(65) == "1:05", "format 1:05 was \(PlaybackClock.format(65))")
    check(PlaybackClock.format(754.9) == "12:34", "format rounds down")
    check(PlaybackClock.format(3723) == "1:02:03", "format with hours")
    check(PlaybackClock.format(-3) == "0:00", "format never negative")
}

// SpotifyPlaybackInfo: the PlaybackStateChanged signal.
do {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let signal: [AnyHashable: Any] = [
        "Player State": "Playing", "Track ID": "spotify:track:42", "Name": "Midnight City", "Artist": "M83",
        "Album": "Hurry Up, We're Dreaming", "Duration": NSNumber(value: 243_000), "Playback Position": NSNumber(value: 12.5),
    ]
    if case .track(let track) = SpotifyPlaybackInfo.parse(signal: signal, at: t0) {
        check(track.trackID == "spotify:track:42" && track.title == "Midnight City" && track.artist == "M83", "signal: names")
        check(track.duration == 243 && track.position == 12.5 && track.positionDate == t0 && track.isPlaying, "signal: timing")
        check(track.artworkURL == nil && track.volume == nil && track.deviceName == nil,
              "signal: no artwork or volume, this Mac")
        check(track.capabilities == SpotifyPlaybackInfo.localCapabilities, "signal: local capabilities")
    } else {
        check(false, "signal with full info decodes to a track")
    }
    var paused = signal
    paused["Player State"] = "Paused"
    paused["Playback Position"] = nil
    if case .track(let track) = SpotifyPlaybackInfo.parse(signal: paused, at: t0) {
        check(!track.isPlaying && track.position == 0, "paused, no position: 0")
    } else {
        check(false, "paused signal decodes to a track")
    }
    check(SpotifyPlaybackInfo.parse(signal: ["Player State": "Stopped"], at: t0) == .stopped, "signal: stopped")
    check(SpotifyPlaybackInfo.parse(signal: nil, at: t0) == .incomplete, "signal without userInfo: incomplete")
    check(SpotifyPlaybackInfo.parse(signal: ["Player State": "Playing"], at: t0) == .incomplete, "signal without track id: incomplete")
}

// SpotifyPlaybackInfo: the text SpotifyScript.readState returns (fields separated by U+001F).
do {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let sep = "\u{1F}"
    let text = ["paused", "spotify:track:7", "Title", "Artist", "Album", "180000", "61500",
                "https://i.scdn.co/image/ab", "70"].joined(separator: sep)
    if case .track(let track) = SpotifyPlaybackInfo.parse(scriptResult: text, at: t0) {
        check(!track.isPlaying && track.duration == 180 && track.position == 61.5, "script: timing")
        check(track.artworkURL == URL(string: "https://i.scdn.co/image/ab") && track.volume == 70, "script: artwork and volume")
        check(track.title == "Title" && track.album == "Album" && track.positionDate == t0, "script: names")
    } else {
        check(false, "script result decodes to a track")
    }
    let local = ["playing", "spotify:local:x", "T", "", "", "1000", "0", "", "101"].joined(separator: sep)
    if case .track(let track) = SpotifyPlaybackInfo.parse(scriptResult: local, at: t0) {
        check(track.artworkURL == nil && track.volume == 100 && track.artist.isEmpty, "script: empty fields, volume clamped")
    } else {
        check(false, "script result with empty fields decodes to a track")
    }
    check(SpotifyPlaybackInfo.parse(scriptResult: "stopped", at: t0) == .stopped, "script: stopped")
    check(SpotifyPlaybackInfo.parse(scriptResult: "garbage", at: t0) == .incomplete, "script: malformed")
}

if failures > 0 {
    print("LogicTests: \(failures) failure(s)")
    exit(1)
}
print("LogicTests: all passed")
