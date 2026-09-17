import AppKit
import SwiftUI

// Written by NotchController, read by NotchView.
final class NotchViewState: ObservableObject {
    @Published var isOpen = false
    @Published var resting: NotchRestingState = .empty
    @Published var tab: NotchTab = .music
    @Published var restingSize: CGSize = .zero
    @Published var openSize: CGSize = .zero
    @Published var notchHeight: CGFloat = 32
}

// Square top (it merges with the notch), rounded bottom corners.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// Root view of the notch panel (spec §4): the resting strip, or the open panel with its two tabs. The panel
// can be larger than the shape while it animates; the shape stays centred at the top.
struct NotchView: View {
    @ObservedObject var state: NotchViewState
    @ObservedObject var model: HeadphonesModel
    @ObservedObject var music: MusicController
    let selectTab: (NotchTab) -> Void

    var body: some View {
        let size = state.isOpen ? state.openSize : state.restingSize
        ZStack(alignment: .top) {
            NotchShape(bottomRadius: state.isOpen ? 22 : 10).fill(Color.black)
            if state.isOpen {
                // Laid out at the final size and clipped by the growing shape, so text never reflows (or spills
                // past the edges) while the spring animates.
                openContent
                    .padding(.top, state.notchHeight)
                    .frame(width: state.openSize.width, height: state.openSize.height)
                    .transition(.opacity)
            } else {
                restingContent
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(NotchShape(bottomRadius: state.isOpen ? 22 : 10))
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
        .frame(height: state.notchHeight)
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
            LevelBars(animating: music.nowPlaying?.isPlaying == true)
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
        VStack(spacing: 10) {
            tabBar
            tabContent.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var tabBar: some View {
        HStack(spacing: 18) {
            tabButton(.music, title: tr("Music"))
            tabButton(.headphones, title: tr("Headphones"))
        }
        .padding(.top, 6)
    }

    private func tabButton(_ tab: NotchTab, title: String) -> some View {
        let selected = state.tab == tab
        return Button { selectTab(tab) } label: {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : .gray)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    if selected { Rectangle().fill(Color.white).frame(height: 2) }
                }
        }
        .buttonStyle(.plain)
    }

    // Both tabs stay in the hierarchy: the menu-style controls (segmented picker, slider, switch) are AppKit
    // views that appear at their natural width for a frame before SwiftUI sizes them, so inserting a tab on
    // each switch made its content spill past the edges.
    private var tabContent: some View {
        ZStack(alignment: .top) {
            tabPage(.music) { Spacer() }        // Task 6: MusicTab
            tabPage(.headphones) { HeadphonesTab(model: model) }
        }
    }

    private func tabPage<Content: View>(_ tab: NotchTab, @ViewBuilder content: () -> Content) -> some View {
        let selected = state.tab == tab
        return content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            } else {
                ZStack {
                    Color(white: 0.2)
                    Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundColor(.gray)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// Four small bars, moving while music plays (resting state 2), frozen when paused.
struct LevelBars: View {
    let animating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(Color.green)
                        .frame(width: 3, height: animating ? 4 + 10 * abs(sin(time * 3 + Double(index) * 1.3)) : 4)
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}
