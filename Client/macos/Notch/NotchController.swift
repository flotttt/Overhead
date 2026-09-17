import AppKit
import Combine
import SwiftUI

// Owns the notch panel (spec §4.3): picks the screen, places and resizes the panel, opens it on hover and
// follows the "Show Notch" option.
final class NotchController {
    private static let shrinkDelay: TimeInterval = 0.35  // lets the closing animation end before the panel shrinks

    private let model: HeadphonesModel
    private let music: MusicController
    private let settings: AppSettings
    private let state = NotchViewState()
    private let panel = NotchPanel.make()
    private var geometry: NotchGeometry?
    private var lastChosenTab: NotchTab?
    private var hoverTimer: Timer?
    private var shrinkWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(model: HeadphonesModel, music: MusicController, settings: AppSettings) {
        self.model = model
        self.music = music
        self.settings = settings

        let container = NotchContainerView()
        let host = NotchHostingView(rootView: NotchView(state: state, model: model, music: music,
                                                        selectTab: { [weak self] tab in self?.select(tab) }))
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.onHoverChange = { [weak self] in self?.scheduleHoverCheck() }
        panel.contentView = container

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
        // receive(on:) hops after @Published stored the new value, so the sinks read current state.
        settings.$showNotch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
        model.$connectionState.combineLatest(music.$status, music.$nowPlaying)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateResting() }
            .store(in: &cancellables)
    }

    // MARK: - Placement

    private func relayout() {
        guard settings.showNotch, let screen = Self.preferredScreen() else {
            geometry = nil
            if state.isOpen {
                state.isOpen = false
                music.notchDidClose()
            }
            shrinkWork?.cancel()
            panel.orderOut(nil)
            return
        }
        let geometry = NotchGeometry(screen: ScreenMetrics(screen))
        self.geometry = geometry
        state.notchHeight = geometry.notch.height
        state.openSize = geometry.open.size
        if state.isOpen { panel.setFrame(geometry.open, display: true) }
        updateResting()
    }

    // The built-in notched screen if there is one, else the primary screen (the one with the menu bar).
    private static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private func updateResting() {
        guard let geometry = geometry else { return }
        let resting = NotchContent.restingState(hasMusic: music.hasMusic, headphonesConnected: model.connected)
        let frame = geometry.restingFrame(for: resting)
        if state.resting != resting || (frame != nil && state.restingSize != frame?.size) {
            withAnimation(animation) {
                state.resting = resting
                if let frame = frame { state.restingSize = frame.size }
            }
        }
        guard !state.isOpen else { return }  // close() re-applies the resting frame
        if let frame = frame {
            setPanelFrame(frame)
            panel.orderFrontRegardless()
        } else {
            hidePanel(after: panel.isVisible ? Self.shrinkDelay : 0)
        }
    }

    // Grows at once (the shape then animates inside the larger panel) or shrinks once the animation is over,
    // so the transparent panel never blocks the menu bar longer than needed.
    private func setPanelFrame(_ target: CGRect) {
        shrinkWork?.cancel()
        let current = panel.frame
        if !panel.isVisible || (target.width >= current.width && target.height >= current.height) {
            panel.setFrame(target, display: true)
        } else {
            let work = DispatchWorkItem { [weak self] in self?.panel.setFrame(target, display: true) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: work)
        }
    }

    private func hidePanel(after delay: TimeInterval) {
        shrinkWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Hover

    // Enter/exit events only schedule a check; the check reads the real pointer position, so a missed event
    // can't leave the notch stuck open or closed.
    private func scheduleHoverCheck() {
        hoverTimer?.invalidate()
        let inside = hoverZone.contains(NSEvent.mouseLocation)
        let delay = inside ? NotchContent.openDelay : NotchContent.closeDelay
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.hoverCheck() }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func hoverCheck() {
        let inside = panel.isVisible && hoverZone.contains(NSEvent.mouseLocation)
        if inside && !state.isOpen {
            open()
        } else if !inside && state.isOpen {
            close()
        }
    }

    private var hoverZone: CGRect {
        guard let geometry = geometry else { return .zero }
        return state.isOpen ? geometry.open : (geometry.restingFrame(for: state.resting) ?? .zero)
    }

    private func open() {
        guard let geometry = geometry else { return }
        state.tab = NotchContent.tabOnOpen(lastChosen: lastChosenTab, hasMusic: music.hasMusic)
        setPanelFrame(geometry.open)
        panel.orderFrontRegardless()
        withAnimation(animation) { state.isOpen = true }
        music.notchDidOpen()
    }

    private func close() {
        withAnimation(animation) { state.isOpen = false }
        music.notchDidClose()
        updateResting()
    }

    private func select(_ tab: NotchTab) {
        lastChosenTab = tab
        state.tab = tab
    }

    // Spring, or a short fade-like ease when "Reduce motion" is on.
    private var animation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.35, dampingFraction: 0.82)
    }
}

private extension ScreenMetrics {
    init(_ screen: NSScreen) {
        self.init(frame: screen.frame,
                  safeAreaTop: screen.safeAreaInsets.top,
                  auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                  auxiliaryTopRight: screen.auxiliaryTopRightArea,
                  menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}
