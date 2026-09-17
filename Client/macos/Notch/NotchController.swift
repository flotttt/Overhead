import AppKit
import Combine
import SwiftUI

// Owns the notch panel (spec §4.3): picks the screen, places the panel, opens it on hover and follows the
// "Show Notch" option.
//
// The panel always keeps the open size: only the SwiftUI shape inside animates. Resizing the window on open
// and close showed a frame of stale content at the new size (things jumped outward, then back). While
// closed, the panel lets every click through, and hover is followed from the pointer position instead of
// tracking areas.
final class NotchController {
    private static let unmountDelay: TimeInterval = 0.4  // lets the closing spring settle first

    private let model: HeadphonesModel
    private let music: MusicController
    private let settings: AppSettings
    private let state = NotchViewState()
    private let panel = NotchPanel.make()
    private var geometry: NotchGeometry?
    private var lastChosenTab: NotchTab?
    private var pointerInside = false
    private var hoverTimer: Timer?
    private var hideWork: DispatchWorkItem?
    private var unmountWork: DispatchWorkItem?
    private var mouseMonitors: [Any] = []
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
        container.onHoverChange = { [weak self] in self?.pointerMoved() }
        panel.contentView = container
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        // Global: the pointer over other apps (the notch is closed, the panel ignores the mouse). Local: over
        // our own windows, the open panel included.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in self?.pointerMoved() }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) {
            mouseMonitors.append(local)
        }

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

    deinit {
        mouseMonitors.forEach(NSEvent.removeMonitor)
    }

    // MARK: - Placement

    private func relayout() {
        guard settings.showNotch, let screen = Self.preferredScreen() else {
            geometry = nil
            if state.isOpen {
                state.isOpen = false
                music.notchDidClose()
            }
            unmountWork?.cancel()
            state.openContentMounted = false
            panel.ignoresMouseEvents = true
            hideWork?.cancel()
            panel.orderOut(nil)
            return
        }
        let geometry = NotchGeometry(screen: ScreenMetrics(screen))
        self.geometry = geometry
        state.notchHeight = geometry.notch.height
        state.openSize = geometry.open.size
        panel.setFrame(geometry.open, display: true)
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
            withAnimation(state.isOpen ? NotchMotion.open : NotchMotion.close) {
                state.resting = resting
                if let frame = frame { state.restingSize = frame.size }
            }
        }
        hideWork?.cancel()
        if frame != nil || state.isOpen {
            panel.orderFrontRegardless()
        } else if panel.isVisible {
            // Nothing to show on a screen without a notch: hide once the shape has shrunk away.
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, !self.state.isOpen else { return }
                self.panel.orderOut(nil)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.unmountDelay, execute: work)
        }
    }

    // MARK: - Hover

    // Only a change of side (in / out) starts the timer, so moving inside doesn't keep postponing the opening;
    // the timer then reads the real pointer position, so a missed event can't leave the notch stuck.
    private func pointerMoved() {
        let inside = isPointerInHoverZone
        guard inside != pointerInside else { return }
        pointerInside = inside
        hoverTimer?.invalidate()
        let delay = inside ? NotchContent.openDelay : NotchContent.closeDelay
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.hoverCheck() }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func hoverCheck() {
        let inside = isPointerInHoverZone
        pointerInside = inside
        if inside && !state.isOpen {
            open()
        } else if !inside && state.isOpen {
            close()
        }
    }

    private var isPointerInHoverZone: Bool {
        guard panel.isVisible, let geometry = geometry else { return false }
        let zone = state.isOpen ? geometry.open : (geometry.restingFrame(for: state.resting) ?? .zero)
        return zone.contains(NSEvent.mouseLocation)
    }

    private func open() {
        unmountWork?.cancel()
        hideWork?.cancel()
        if !state.openContentMounted { state.tab = NotchContent.tabOnOpen(lastChosen: lastChosenTab, hasMusic: music.hasMusic) }
        state.openContentMounted = true
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        withAnimation(NotchMotion.open) { state.isOpen = true }
        music.notchDidOpen()
    }

    private func close() {
        panel.ignoresMouseEvents = true  // clicks reach the apps below while the shape shrinks
        withAnimation(NotchMotion.close) { state.isOpen = false }
        music.notchDidClose()
        updateResting()
        // The open content shrinks and fades with the shape (it stays mounted while closing), then leaves the
        // hierarchy so its timelines stop.
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.state.isOpen else { return }
            self.state.openContentMounted = false
        }
        unmountWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.unmountDelay, execute: work)
    }

    private func select(_ tab: NotchTab) {
        lastChosenTab = tab
        withAnimation(NotchMotion.content) { state.tab = tab }
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
