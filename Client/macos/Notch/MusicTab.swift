import SwiftUI

// Notch player page (spec §4.2): artwork, title and artist; progress; headphones, previous, play/pause, next,
// shuffle. The volume button swaps the progress bar for Spotify's volume bar for a few seconds. Sizes follow
// the notch zoom; extra height grows the artwork.
struct MusicTab: View {
    private static let volumeAutoHide: TimeInterval = 4

    @ObservedObject var music: MusicController
    let showHeadphones: () -> Void
    @Environment(\.notchScale) private var s
    @State private var seekValue: Double?    // while dragging the progress bar
    @State private var volumeValue: Double?  // while dragging the volume bar
    @State private var showVolume = false
    @State private var volumeHideWork: DispatchWorkItem?

    // Explicit: the private @State properties would otherwise make the memberwise init private.
    init(music: MusicController, showHeadphones: @escaping () -> Void) {
        _music = ObservedObject(wrappedValue: music)
        self.showHeadphones = showHeadphones
    }

    var body: some View {
        switch music.status {
        case .notRunning:
            message(tr("Spotify isn't open"), button: tr("Open Spotify")) { music.launchPlayer() }
        case .permissionDenied:
            message(tr("SonyBridge isn't allowed to control Spotify."), button: tr("Open Settings")) {
                music.openAutomationSettings()
            }
        case .ready:
            if let track = music.nowPlaying {
                player(track)
            } else {
                message(tr("Nothing playing"), button: nil) {}
            }
        }
    }

    private func message(_ text: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10 * s) {
            Text(text).font(.system(size: 12 * s)).foregroundColor(.gray).multilineTextAlignment(.center)
            if let button = button {
                NotchPillButton(title: button, action: action)
            }
            Spacer(minLength: 0)
            HStack {
                iconButton("headphones", label: tr("Headphones"), action: showHeadphones)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6 * s)
    }

    private func player(_ track: NowPlaying) -> some View {
        GeometryReader { proxy in
            player(track, artwork: artworkSize(forHeight: proxy.size.height))
        }
    }

    // 50 pt at the default height; each extra point of height gives the artwork 0.6 pt, within 44...88 (× zoom).
    private func artworkSize(forHeight height: CGFloat) -> CGFloat {
        min(88 * s, max(44 * s, 50 * s + (height - 112 * s) * 0.6))
    }

    private func player(_ track: NowPlaying, artwork: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12 * s) {
                ArtworkView(image: music.artwork, size: artwork, cornerRadius: artwork * 0.2)
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(track.title).font(.system(size: 14 * s, weight: .semibold)).foregroundColor(.white)
                    Text(track.artist).font(.system(size: 13 * s)).foregroundColor(.gray)
                }
                .lineLimit(1)
                .id(track.trackID)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
                Spacer(minLength: 6 * s)
                LevelBars(animating: track.isPlaying, color: music.artworkTint)
            }
            .animation(NotchMotion.content, value: track.trackID)
            Spacer(minLength: 8 * s)
            ZStack {
                progress(track)
                    .modifier(FadeScale(amount: showVolume ? 1 : 0))
                    .allowsHitTesting(!showVolume)
                volume(track)
                    .modifier(FadeScale(amount: showVolume ? 0 : 1))
                    .allowsHitTesting(showVolume)
            }
            .animation(NotchMotion.content, value: showVolume)
            Spacer(minLength: 6 * s)
            HStack(spacing: 0) {
                iconButton("headphones", label: tr("Headphones"), action: showHeadphones)
                Spacer()
                iconButton("backward.fill", size: 17, color: .white, label: tr("Previous track")) { music.previous() }
                Spacer()
                iconButton(track.isPlaying ? "pause.fill" : "play.fill", size: 21, color: .white,
                           label: tr("Play or pause")) { music.playPause() }
                    .animation(NotchMotion.content, value: track.isPlaying)
                Spacer()
                iconButton("forward.fill", size: 17, color: .white, label: tr("Next track")) { music.next() }
                Spacer()
                iconButton("shuffle", color: track.isShuffling == true ? .white : .gray, label: tr("Shuffle")) {
                    music.toggleShuffle()
                }
                .disabled(track.isShuffling == nil)
                Spacer()
                iconButton(showVolume ? "speaker.wave.2.fill" : "speaker.wave.2", color: showVolume ? .white : .gray,
                           label: tr("Spotify volume")) { toggleVolume() }
                .disabled(!track.capabilities.canSetVolume || track.volume == nil)
            }
        }
    }

    // Redrawn once a second, only while the notch is open (this view only exists then).
    private func progress(_ track: NowPlaying) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = seekValue ?? PlaybackClock.position(of: track, at: context.date)
            HStack(spacing: 8 * s) {
                timeLabel(PlaybackClock.format(position))
                FlatSlider(value: position, range: 0...max(track.duration, 1), smoothing: seekValue == nil) { value, final in
                    seekValue = final ? nil : value
                    music.seek(to: value, final: final)
                }
                .disabled(!track.capabilities.canSeek || track.duration <= 0)
                timeLabel(PlaybackClock.format(track.duration))
            }
        }
    }

    private func volume(_ track: NowPlaying) -> some View {
        HStack(spacing: 8 * s) {
            Image(systemName: "speaker.fill").font(.system(size: 10 * s)).foregroundColor(.gray).frame(width: 34 * s)
            FlatSlider(value: volumeValue ?? Double(track.volume ?? 0), range: 0...100) { value, final in
                volumeValue = final ? nil : value
                music.setVolume(Int(value.rounded()), final: final)
                scheduleVolumeHide()
            }
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10 * s)).foregroundColor(.gray).frame(width: 34 * s)
        }
    }

    private func timeLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11 * s).monospacedDigit())
            .foregroundColor(.gray)
            .frame(width: 36 * s)
    }

    private func iconButton(_ symbol: String, size: CGFloat = 14, color: Color = .gray, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * s))
                .foregroundColor(color)
                .symbolReplaceTransition()
                .frame(width: 28 * s, height: 26 * s)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }

    private func toggleVolume() {
        withAnimation(NotchMotion.content) { showVolume.toggle() }
        if showVolume { scheduleVolumeHide() } else { volumeHideWork?.cancel() }
    }

    // The volume bar folds back once it hasn't been touched for a few seconds.
    private func scheduleVolumeHide() {
        volumeHideWork?.cancel()
        let work = DispatchWorkItem { withAnimation(NotchMotion.content) { showVolume = false } }
        volumeHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.volumeAutoHide, execute: work)
    }
}
