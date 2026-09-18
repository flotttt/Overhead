import AppKit
import Combine
import SwiftUI

// Owns the notch panel: picks the screen, places the panel, opens it on hover and follows the
// "Show Notch" option.
//
// The panel always keeps the largest open size the Notch Size options allow: only the SwiftUI shape inside
// animates, including while the size is changed. Resizing the window on open
// and close showed a frame of stale content at the new size (things jumped outward, then back). While
// closed, the panel lets every click through, and hover is followed from the pointer position instead of
// tracking areas.
final class NotchController {
    private static let unmountDelay: TimeInterval = 0.4  // lets the closing spring settle first
    private static let closedPreviewTime: TimeInterval = 1  // closed-width preview, then back to the open notch

    private let model: HeadphonesModel
    private let music: MusicController
    private let settings: AppSettings
    private let state = NotchViewState()
    private let panel = NotchPanel.make()
    private var geometry: NotchGeometry?
    private var lastChosenTab: NotchTab?
    private var pointerInside = false
    private var scrollGesture = NotchScrollGesture()
    private var gestureVolume: Int?  // volume being set by scrolling, sent for good once the scrolling stops
    private var volumeCommitWork: DispatchWorkItem?
    private var previewing = false  // Notch Size submenu open: the pointer neither opens nor closes the notch
    private var reopenWork: DispatchWorkItem?
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
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.scrolled(event)
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.scrolled(event)
            return event
        }) {
            mouseMonitors.append(local)
        }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
        // receive(on:) hops after @Published stored the new value, so the sinks read current state.
        settings.$showNotch.combineLatest(settings.$usageMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, mode in
                self?.state.headphonesEnabled = mode.usesHeadphones
                if !mode.usesHeadphones { self?.select(.music) }
                self?.relayout()
            }
            .store(in: &cancellables)
        // A size slider shows what it changes: the open notch for its width, height and text size, the closed
        // notch for the closed width.
        Publishers.Merge3(settings.$notchWidth.dropFirst(), settings.$notchHeight.dropFirst(), settings.$notchZoom.dropFirst())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sizeChanged(showOpen: true) }
            .store(in: &cancellables)
        settings.$notchSideWidth.dropFirst().merge(with: settings.$notchArtwork.dropFirst())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sizeChanged(showOpen: false) }
            .store(in: &cancellables)
        Publishers.CombineLatest4(settings.$hapticOnOpen, settings.$hapticOnButtons, settings.$hapticOnSkip,
                                  settings.$hapticOnVolume)
            .sink { open, buttons, skip, volume in
                var events = Set<NotchHaptics.Event>()
                if open { events.insert(.notchOpens) }
                if buttons { events.insert(.buttonPress) }
                if skip { events.insert(.trackSkip) }
                if volume { events.insert(.volumeDetent) }
                NotchHaptics.enabledEvents = events
            }
            .store(in: &cancellables)
        settings.$artworkGlow
            .sink { [weak self] in self?.state.artworkGlow = $0 }
            .store(in: &cancellables)
        settings.$progressRing
            .sink { [weak self] in self?.state.progressRing = $0 }
            .store(in: &cancellables)
        settings.$headphonesBattery
            .sink { [weak self] in self?.state.headphonesBattery = $0 }
            .store(in: &cancellables)
        settings.$glowSize
            .sink { [weak self] in self?.state.glowSize = CGFloat($0) }
            .store(in: &cancellables)
        settings.$hapticStrength
            .sink { NotchHaptics.strength = $0 }
            .store(in: &cancellables)
        settings.$notchPreviewing
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.setPreviewing(on) }
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
        guard settings.showNotch, settings.usageMode.usesNotch, let screen = Self.preferredScreen() else {
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
        let metrics = ScreenMetrics(screen)
        let layout = settings.notchLayout
        let geometry = NotchGeometry(screen: metrics, layout: layout)
        self.geometry = geometry
        state.notchHeight = geometry.notch.height
        state.openSize = geometry.open.size
        state.sideExtension = layout.sideExtension
        state.contentScale = layout.contentScale
        state.restingScale = layout.restingScale
        state.restingArtworkSize = layout.restingArtworkSize(notchHeight: geometry.notch.height)
        let largest = NotchLayout(openSize: CGSize(width: NotchLayout.widthRange.upperBound,
                                                   height: NotchLayout.heightRange.upperBound),
                                  sideExtension: NotchLayout.sideRange.upperBound, zoom: 1)
        let panelFrame = NotchGeometry(screen: metrics, layout: largest).open
        if panel.frame != panelFrame { panel.setFrame(panelFrame, display: true) }
        updateResting()
    }

    // The built-in notched screen if there is one, else the primary screen (the one with the menu bar).
    private static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private func updateResting() {
        guard let geometry = geometry else { return }
        let resting = NotchContent.restingState(hasMusic: music.hasMusic, headphonesConnected: model.connected,
                                                mode: settings.usageMode)
        let frame = geometry.restingFrame(for: resting)
        if state.resting != resting || (frame != nil && state.restingSize != frame?.size) {
            withAnimation(state.isOpen ? NotchMotion.open : NotchMotion.close) {
                state.resting = resting
                if let frame = frame { state.restingSize = frame.size }
            }
        }
        updateTrailingHover()
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
        updateTrailingHover()
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
        if inside && !state.isOpen && !previewing {
            open()
        } else if !inside && state.isOpen && !previewing {
            close()
        }
    }

    private var isPointerInHoverZone: Bool {
        guard panel.isVisible, let geometry = geometry else { return false }
        let pointer = NSEvent.mouseLocation
        if state.isOpen { return geometry.open.contains(pointer) }
        // The resting music control is clicked, not a way to open the notch.
        if hasRestingMusicControl && geometry.restingTrailingZone.contains(pointer) { return false }
        return geometry.restingFrame(for: state.resting)?.contains(pointer) ?? false
    }

    private var hasRestingMusicControl: Bool {
        state.resting == .musicAndHeadphones || state.resting == .musicOnly
    }

    // While closed, the pointer over the right widening swaps the level bars for next / play, and the panel
    // takes the mouse there (and only there) so the button can be clicked.
    private func updateTrailingHover() {
        let hovered = !state.isOpen && panel.isVisible && hasRestingMusicControl
            && (geometry?.restingTrailingZone.contains(NSEvent.mouseLocation) ?? false)
        if hovered != state.trailingHovered {
            withAnimation(NotchMotion.content) { state.trailingHovered = hovered }
        }
        panel.ignoresMouseEvents = !(state.isOpen || hovered)
    }

    private func open() {
        unmountWork?.cancel()
        hideWork?.cancel()
        if !state.openContentMounted {
            let tab = NotchContent.tabOnOpen(lastChosen: lastChosenTab, hasMusic: music.hasMusic)
            state.tab = settings.usageMode.usesHeadphones ? tab : .music
        }
        state.openContentMounted = true
        state.trailingHovered = false
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        withAnimation(NotchMotion.open) { state.isOpen = true }
        if !previewing { NotchHaptics.tap(.notchOpens) }
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

    // MARK: - Gestures

    // Over the notch (closed, or open on the player): swipe for previous / next, scroll for Spotify's volume.
    private func scrolled(_ event: NSEvent) {
        let preferences = settings.gesturePreferences
        guard preferences.swipeToSkip || preferences.scrollForVolume,
              panel.isVisible, let geometry = geometry, music.status == .ready, music.hasMusic,
              !state.isOpen || state.tab == .music else { return }
        let zone = state.isOpen ? geometry.open : (geometry.restingFrame(for: state.resting) ?? .zero)
        guard zone.contains(NSEvent.mouseLocation) else { return }

        let phase: ScrollSample.Phase
        if !event.momentumPhase.isEmpty {
            phase = .momentum
        } else if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else {
            phase = event.phase.isEmpty ? .none : .changed
        }
        let sample = ScrollSample(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                  precise: event.hasPreciseScrollingDeltas,
                                  inverted: event.isDirectionInvertedFromDevice, phase: phase)
        switch scrollGesture.handle(sample)?.applying(settings.gesturePreferences) {
        case .nextTrack?:
            NotchHaptics.tap(.trackSkip)
            music.next()
        case .previousTrack?:
            NotchHaptics.tap(.trackSkip)
            music.previous()
        case .volume(let change)?: changeVolume(by: change)
        case nil: break
        }
    }

    private func changeVolume(by change: Int) {
        guard let base = gestureVolume ?? music.nowPlaying?.volume else { return }
        let volume = min(100, max(0, base + change))
        if VolumeDetent.crossed(from: base, to: volume) { NotchHaptics.tap(.volumeDetent) }
        gestureVolume = volume
        state.scrolledVolume = volume
        music.setVolume(volume, final: false)
        volumeCommitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let volume = self.gestureVolume else { return }
            self.gestureVolume = nil
            self.music.setVolume(volume, final: true)
            self.state.scrolledVolume = nil
        }
        volumeCommitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // The Notch Size submenu opens the notch as a live preview; closing the menu hands it back to the pointer.
    private func setPreviewing(_ on: Bool) {
        previewing = on
        reopenWork?.cancel()
        if on {
            if geometry != nil && !state.isOpen { open() }
        } else {
            hoverCheck()
        }
    }

    // Width, height and text size show on the open notch. The closed width and artwork close it while they move,
    // then reopens it a second after the last change, so the other sliders find it open again.
    private func sizeChanged(showOpen: Bool) {
        withAnimation(NotchMotion.content) { relayout() }
        guard previewing, geometry != nil else { return }
        reopenWork?.cancel()
        if showOpen {
            if !state.isOpen { open() }
            return
        }
        if state.isOpen { close() }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.previewing, !self.state.isOpen else { return }
            self.open()
        }
        reopenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closedPreviewTime, execute: work)
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
