import AppKit
import SwiftUI

// Written by NotchController, read by NotchView.
final class NotchViewState: ObservableObject {
    @Published var isOpen = false
    @Published var openContentMounted = false  // true while open, and while the closing animation plays
    @Published var resting: NotchRestingState = .empty
    @Published var tab: NotchTab = .music
    @Published var restingSize: CGSize = .zero
    @Published var openSize: CGSize = .zero
    @Published var notchHeight: CGFloat = 32
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

// Root view of the notch panel (spec §4): the resting strip, or the open panel (player or headphones page). The panel
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
                    .padding(.top, state.notchHeight)
                    .frame(width: state.openSize.width, height: state.openSize.height)
                    .modifier(FadeScale(amount: state.isOpen ? 0 : 1, scale: NotchMotion.morphScale))
                    .allowsHitTesting(state.isOpen)
                    .transition(NotchMotion.morph)
            }
            // Always mounted and faded on isOpen: an inserted resting strip (transition) didn't come back after
            // a close while the open content was still mounted.
            restingContent
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

    // MARK: - Resting (spec §4.1)

    private var restingContent: some View {
        HStack(spacing: 0) {
            leadingItem.frame(width: NotchGeometry.sideExtension)
            Spacer(minLength: 0)
            trailingItem.frame(width: NotchGeometry.sideExtension)
        }
        // Explicit width: while the (wider) open content is still mounted during a close, the strip otherwise
        // took the open width, so the artwork and mode icon sat outside the shape (cut off), then jumped back.
        .frame(width: state.restingSize.width, height: state.notchHeight)
    }

    @ViewBuilder private var leadingItem: some View {
        switch state.resting {
        case .musicAndHeadphones, .musicOnly:
            ArtworkView(image: music.artwork, size: 20, cornerRadius: 5)
        case .headphonesOnly:
            Image(systemName: "headphones").font(.system(size: 13)).foregroundColor(.white)
        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder private var trailingItem: some View {
        switch state.resting {
        case .musicAndHeadphones, .headphonesOnly:
            Image(systemName: Self.modeSymbol(model.mode)).font(.system(size: 13)).foregroundColor(.white)
        case .musicOnly:
            LevelBars(animating: music.nowPlaying?.isPlaying == true, color: music.artworkTint)
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

    // MARK: - Open (spec §4.2)

    private var openContent: some View {
        // Both pages stay in the hierarchy (switching is then a cross-slide, not an insertion), the hidden one
        // neither drawn, clickable nor read by VoiceOver.
        ZStack(alignment: .top) {
            page(.music) { MusicTab(music: music, showHeadphones: { selectTab(.headphones) }) }
            page(.headphones) { HeadphonesTab(model: model, back: { selectTab(.music) }) }
        }
        .padding(.top, 8)
        .padding(.horizontal, Self.openFlare + 16)
        .padding(.bottom, 14)
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

// Album artwork, or a placeholder note while it loads (or for tracks without one).
struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            } else {
                ZStack {
                    Color(white: 0.2)
                    Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundColor(.gray)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .animation(.easeInOut(duration: 0.3), value: image.map(ObjectIdentifier.init))
    }
}

// Four small bars in the artwork's colour, moving while music plays, frozen when paused.
struct LevelBars: View {
    let animating: Bool
    var color: NSColor?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(color.map(Color.init(nsColor:)) ?? Color(white: 0.85))
                        .frame(width: 3, height: animating ? 4 + 10 * abs(sin(time * 3 + Double(index) * 1.3)) : 4)
                }
            }
            .frame(height: 14, alignment: .bottom)
            .animation(.easeOut(duration: 0.3), value: animating)
        }
    }
}
