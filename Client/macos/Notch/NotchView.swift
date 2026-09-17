import AppKit
import SwiftUI

// Written by NotchController, read by NotchView.
final class NotchViewState: ObservableObject {
    @Published var isOpen = false
    @Published var openContentMounted = false  // true while open, and while the closing animation plays
    @Published var trailingHovered = false     // pointer over the resting music control
    @Published var scrolledVolume: Int?         // Spotify volume being set by scrolling over the notch
    @Published var artworkGlow = true           // Options › Glow
    @Published var glowSize: CGFloat = 1        // times the default glow size
    @Published var resting: NotchRestingState = .empty
    @Published var tab: NotchTab = .music
    @Published var restingSize: CGSize = .zero
    @Published var openSize: CGSize = .zero
    @Published var notchHeight: CGFloat = 32
    @Published var sideExtension = NotchLayout.default.sideExtension
    @Published var contentScale: CGFloat = 1  // text and icon zoom, open notch
    @Published var restingScale: CGFloat = 1  // same, resting icons
    @Published var restingArtworkSize = NotchLayout.default.restingArtwork
}

// Merges with the notch: the top corners flare out into the menu bar (concave, `topRadius` wide on each side,
// inside the rect), the bottom corners are rounded.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { (topRadius, bottomRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let body = rect.insetBy(dx: top, dy: 0)
        let bottom = min(bottomRadius, body.width / 2, rect.height - top)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: body.maxX, y: rect.minY + top), control: CGPoint(x: body.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: body.maxX, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: body.maxX - bottom, y: rect.maxY), control: CGPoint(x: body.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: body.minX + bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: body.minX, y: rect.maxY - bottom), control: CGPoint(x: body.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: body.minX, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: body.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// Root view of the notch panel: the resting strip, or the open panel (player or headphones page). The panel
// can be larger than the shape while it animates; the shape stays centred at the top.
struct NotchView: View {
    static let openFlare: CGFloat = 10

    @ObservedObject var state: NotchViewState
    @ObservedObject var model: HeadphonesModel
    @ObservedObject var music: MusicController
    let selectTab: (NotchTab) -> Void

    var body: some View {
        let size = state.isOpen ? state.openSize : state.restingSize
        let shape = NotchShape(topRadius: state.isOpen ? Self.openFlare : 0, bottomRadius: state.isOpen ? 24 : 10)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if state.openContentMounted {
                // Laid out at the final size and clipped by the growing shape, so text never reflows (or spills
                // past the edges) while the spring animates. Grows in with a transition; shrinks out through the
                // modifier below, since SwiftUI skipped the removal transition (content vanished at once).
                openContent
                    .environment(\.notchScale, state.contentScale)
                    .padding(.top, state.notchHeight)
                    .frame(width: state.openSize.width, height: state.openSize.height)
                    .background(artworkGlow)
                    .modifier(FadeScale(amount: state.isOpen ? 0 : 1, scale: NotchMotion.morphScale))
                    .allowsHitTesting(state.isOpen)
                    .transition(NotchMotion.morph)
            }
            // Always mounted and faded on isOpen: an inserted resting strip (transition) didn't come back after
            // a close while the open content was still mounted.
            restingContent
                .environment(\.notchScale, state.restingScale)
                .opacity(state.isOpen ? 0 : 1)
                .animation(NotchMotion.resting(open: state.isOpen), value: state.isOpen)
                .allowsHitTesting(!state.isOpen)
        }
        // Top-aligned: the open content is taller than the shape while it grows, and the default (centred)
        // alignment pushed it up past the top of the screen, then slid it down — the bar seemed to jump.
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Resting

    private var restingContent: some View {
        HStack(spacing: 0) {
            leadingItem.frame(width: state.sideExtension)
            Spacer(minLength: 0)
            trailingItem.frame(width: state.sideExtension)
        }
        // Explicit width: while the (wider) open content is still mounted during a close, the strip otherwise
        // took the open width, so the artwork and mode icon sat outside the shape (cut off), then jumped back.
        .frame(width: state.restingSize.width, height: state.notchHeight)
    }

    @ViewBuilder private var leadingItem: some View {
        switch state.resting {
        case .musicAndHeadphones, .musicOnly:
            ArtworkView(image: music.artwork, trackID: music.nowPlaying?.trackID,
                        isBackward: { [music] in music.trackChangeIsBackward },
                        size: state.restingArtworkSize,
                        cornerRadius: state.restingArtworkSize * 0.25)
        case .headphonesOnly:
            Image(systemName: "headphones").font(.system(size: 13 * state.restingScale)).foregroundColor(.white)
        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder private var trailingItem: some View {
        switch state.resting {
        case .musicAndHeadphones, .musicOnly:
            RestingMusicControl(music: music, hovered: state.trailingHovered)
        case .headphonesOnly:
            Image(systemName: Self.modeSymbol(model.mode)).font(.system(size: 13 * state.restingScale)).foregroundColor(.white)
        case .empty:
            EmptyView()
        }
    }

    private static func modeSymbol(_ mode: SHCAmbientMode) -> String {
        switch mode {
        case .noiseCanceling: return "headphones.circle.fill"
        case .ambientSound: return "ear.and.waveform"
        default: return "circle.slash"
        }
    }

    // MARK: - Open

    // A soft light in the artwork's colour, coming from where the artwork sits and fading over the player, like
    // the iPhone's lock screen. Its colour glides to the next track's; it fades out on the headphones page.
    private var artworkGlow: some View {
        let tint = music.artworkTint.map(Color.init(nsColor:)) ?? .clear
        let visible = state.artworkGlow && state.tab == .music && music.hasMusic && music.artworkTint != nil
        return RadialGradient(colors: [tint.opacity(0.42), tint.opacity(0.12), .clear],
                              center: UnitPoint(x: 0.17, y: 0.4), startRadius: 0,
                              endRadius: state.openSize.width * 0.8 * state.glowSize)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.6), value: music.artworkTint)
            .animation(NotchMotion.content, value: visible)
            .allowsHitTesting(false)
    }

    private var openContent: some View {
        // Both pages stay in the hierarchy (switching is then a cross-slide, not an insertion), the hidden one
        // neither drawn, clickable nor read by VoiceOver.
        ZStack(alignment: .top) {
            page(.music) {
                MusicTab(music: music, scrolledVolume: state.scrolledVolume, showHeadphones: { selectTab(.headphones) })
            }
            page(.headphones) { HeadphonesTab(model: model, back: { selectTab(.music) }) }
        }
        .padding(.top, 8 * state.contentScale)
        .padding(.horizontal, Self.openFlare + 16 * state.contentScale)
        .padding(.bottom, 14 * state.contentScale)
    }

    // The player slides off to the left, the headphones page comes in from the right (and back). No blur: it
    // made each frame of the switch expensive.
    private func page<Content: View>(_ tab: NotchTab, @ViewBuilder content: () -> Content) -> some View {
        let selected = state.tab == tab
        let motion = !NotchMotion.reduceMotion
        return content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scaleEffect(selected || !motion ? 1 : 0.96)
            .offset(x: selected || !motion ? 0 : (tab == .music ? -24 : 24))
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
    }
}

// Album artwork, or a placeholder note while it loads (or for tracks without one). When `trackID` changes the
// card flips like Spotify's, backwards after "previous".
struct ArtworkView: View {
    let image: NSImage?
    var trackID: String?
    var isBackward: () -> Bool = { false }  // read when the track changes
    let size: CGFloat
    let cornerRadius: CGFloat

    @StateObject private var flip = ArtworkFlip()

    var body: some View {
        face(flip.shown)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .rotation3DEffect(.degrees(flip.angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .onAppear { flip.start(image: image, trackID: trackID) }
            // Only the values passed in are new: the closure itself belongs to the previous render, so reading
            // `image` or `trackID` in it gives the old ones.
            .onChange(of: trackID) { newTrackID in flip.trackChanged(to: newTrackID, backward: isBackward()) }
            .onChange(of: image) { newImage in flip.imageChanged(to: newImage) }
    }

    @ViewBuilder private func face(_ image: NSImage?) -> some View {
        if let image = image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(white: 0.2)
                Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundColor(.gray)
            }
        }
    }
}

// The flip itself. A reference type on purpose: its delayed steps must read the latest artwork, whereas a
// closure in a View struct keeps the values of the render that created it (which showed a previous track's
// artwork after quick skips). The card turns to its edge, waits there for the new track's artwork (downloaded
// after the track change, at most `flipWait`), then turns the rest of the way showing it.
final class ArtworkFlip: ObservableObject {
    private static let flipWait: TimeInterval = 1
    private static let halfFlip: TimeInterval = 0.16

    @Published private(set) var shown: NSImage?
    @Published private(set) var angle: Double = 0

    private var latestImage: NSImage?
    private var latestTrackID: String?
    private var shownTrackID: String?
    private var atEdge = false
    private var receivedImage = false  // an artwork was published since the track changed (maybe the same album's)
    private var backward = false
    private var generation = 0  // bumped on every track change; older delayed steps give up

    func start(image: NSImage?, trackID: String?) {
        latestImage = image
        latestTrackID = trackID
        shown = image
        shownTrackID = trackID
    }

    // Called before imageChanged when both change together: the new artwork is read later, at the edge.
    func trackChanged(to trackID: String?, backward: Bool) {
        latestTrackID = trackID
        guard trackID != shownTrackID else { return }
        if NotchMotion.reduceMotion || shownTrackID == nil {
            withAnimation(.easeInOut(duration: 0.25)) { shown = latestImage }
            shownTrackID = trackID
            return
        }
        generation += 1
        let current = generation
        self.backward = backward
        receivedImage = false
        if !atEdge {
            withAnimation(.easeIn(duration: Self.halfFlip)) { angle = backward ? -90 : 90 }
        }
        let previousImage = shown
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.halfFlip) { [weak self] in
            guard let self = self, self.generation == current else { return }
            self.atEdge = true
            // The new artwork may already be there (cached, or the same album's); otherwise wait for it, not forever.
            if let image = self.latestImage, image !== previousImage || self.receivedImage {
                self.flipIn()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.flipWait) { [weak self] in
                guard let self = self, self.generation == current else { return }
                self.flipIn()
            }
        }
    }

    func imageChanged(to image: NSImage?) {
        latestImage = image
        if image != nil && latestTrackID != shownTrackID { receivedImage = true }
        if atEdge {
            if image != nil { flipIn() }
        } else if latestTrackID == shownTrackID {
            // Same track, artwork arriving late (or first launch): no flip, just a fade.
            withAnimation(.easeInOut(duration: 0.25)) { shown = image }
        }
    }

    private func flipIn() {
        guard atEdge else { return }
        atEdge = false
        generation += 1  // cancels a pending timeout
        shown = latestImage
        shownTrackID = latestTrackID
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { angle = backward ? 90 : -90 }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { angle = 0 }
    }
}

// Right side of the resting notch while music is loaded: the level bars in the artwork's colour, replaced on
// hover by "next track" while playing, or "play" while paused.
struct RestingMusicControl: View {
    @ObservedObject var music: MusicController
    let hovered: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        let playing = music.nowPlaying?.isPlaying == true
        ZStack {
            LevelBars(animating: playing && !hovered, color: music.artworkTint)
                .modifier(FadeScale(amount: hovered ? 1 : 0, scale: 0.6))
            Button {
                if playing { music.next() } else { music.playPause() }
            } label: {
                Image(systemName: playing ? "forward.fill" : "play.fill")
                    .font(.system(size: 13 * s))
                    .foregroundColor(.white)
                    .symbolReplaceTransition()
                    .frame(width: 30 * s, height: 26 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(playing ? tr("Next track") : tr("Play or pause"))
            .modifier(FadeScale(amount: hovered ? 0 : 1, scale: 0.6))
            .allowsHitTesting(hovered)
            .animation(NotchMotion.content, value: playing)
        }
    }
}

// Four small bars in the artwork's colour, moving while music plays, frozen when paused.
struct LevelBars: View {
    let animating: Bool
    var color: NSColor?
    @Environment(\.notchScale) private var s

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2 * s) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(color.map(Color.init(nsColor:)) ?? Color(white: 0.85))
                        .frame(width: 3 * s, height: (animating ? 4 + 10 * abs(sin(time * 3 + Double(index) * 1.3)) : 4) * s)
                }
            }
            .frame(height: 14 * s, alignment: .bottom)
            .animation(.easeOut(duration: 0.3), value: animating)
        }
    }
}
