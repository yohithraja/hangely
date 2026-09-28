//
//  OverlayWindowController.swift
//  Hangly
//
//  Owns the overlay panel's lifetime, placement, configuration and frame clock.
//

import AppKit
import OSLog
import SwiftUI

/// Keeps the overlay panel in sync with `OverlaySettings`, with the display layout,
/// and with the running simulation.
///
/// This is the one place that touches the window server. It reacts to two streams —
/// settings changes and display-configuration changes — and owns the display link
/// that advances the rope, because the link has to be created from the view that is
/// actually on screen.
///
/// The panel is created lazily and torn down entirely when the overlay is disabled,
/// so a hidden overlay costs nothing and its clock stops with it.
@MainActor
final class OverlayWindowController {
    private let settingsStore: SettingsStore
    private let screenObserver: ScreenObserver
    private let accessibility: AccessibilityPreferences
    private let viewModel: OverlayViewModel
    private let settingsStream: ObservationStream<OverlaySettings>
    private let clock = SimulationClock()

    private var panel: OverlayPanel?
    private var settingsTask: Task<Void, Never>?
    private var screenTask: Task<Void, Never>?
    private var isFadingOut = false
    private var cursorIsPushed = false
    private var pushedCursorIsClosedHand = false

    /// Fade duration for showing and hiding the overlay. Zero under Reduce Motion.
    private static let fadeDuration: TimeInterval = 0.28

    init(
        settingsStore: SettingsStore,
        screenObserver: ScreenObserver,
        charmManager: CharmManager,
        importCoordinator: CharmImportCoordinator,
        audio: AudioService,
        accessibility: AccessibilityPreferences
    ) {
        self.settingsStore = settingsStore
        self.screenObserver = screenObserver
        self.accessibility = accessibility
        self.viewModel = OverlayViewModel(
            settingsStore: settingsStore,
            charmManager: charmManager,
            importCoordinator: importCoordinator,
            audio: audio,
            accessibility: accessibility
        )
        self.settingsStream = ObservationStream { settingsStore.settings.overlay }
    }

    /// Starts presenting the overlay and observing everything that affects it.
    func start() {
        guard settingsTask == nil else { return }

        screenObserver.start()

        let settingsValues = settingsStream.values
        settingsTask = Task { @MainActor [weak self] in
            for await overlay in settingsValues {
                self?.apply(overlay)
            }
        }
        settingsStream.start()

        let screenChanges = screenObserver.changes
        screenTask = Task { @MainActor [weak self] in
            for await _ in screenChanges {
                Logger.overlay.diagnostic("Display configuration changed; re-anchoring overlay.")
                self?.reposition()
            }
        }
    }

    /// Tears down the panel and stops observing.
    func stop() {
        settingsTask?.cancel()
        settingsTask = nil
        screenTask?.cancel()
        screenTask = nil

        settingsStream.stop()
        screenObserver.stop()
        teardownPanel()
    }

    // MARK: - Applying settings

    private func apply(_ overlay: OverlaySettings) {
        guard overlay.isEnabled else {
            fadeOutAndTeardown()
            return
        }

        let isNew = panel == nil
        let panel = ensurePanel()
        isFadingOut = false
        panel.collectionBehavior = OverlayPanel.collectionBehavior(joinsAllSpaces: overlay.joinsAllSpaces)

        position(panel, using: overlay)
        viewModel.start()
        updateInteractivity()

        // `orderFrontRegardless` shows the panel without activating Hangly, which
        // would otherwise pull focus away from the user's current app.
        panel.orderFrontRegardless()
        if isNew {
            fade(panel, to: 1)
        } else {
            panel.alphaValue = 1
        }
    }

    /// Show and hide are a short fade rather than a cut. Under Reduce Motion the
    /// change is immediate.
    private func fade(_ panel: OverlayPanel, to alpha: Double, completion: (@MainActor () -> Void)? = nil) {
        guard !accessibility.reducesMotion else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            Task { @MainActor in completion?() }
        }
    }

    private func fadeOutAndTeardown() {
        guard let panel, !isFadingOut else { return }
        isFadingOut = true
        fade(panel, to: 0) { [weak self] in
            guard let self, self.isFadingOut else { return }
            self.teardownPanel()
        }
    }

    /// Re-anchors using the current settings. Called when displays change.
    private func reposition() {
        guard let panel else { return }
        position(panel, using: settingsStore.settings.overlay)
    }

    private func position(_ panel: OverlayPanel, using overlay: OverlaySettings) {
        guard let screen = NSScreen.hanglyPreferred else {
            Logger.overlay.warning("No screen available; leaving overlay where it is.")
            return
        }

        let size = AppConstants.Overlay.baseSize.scaled(by: overlay.scale)
        let bounds = screen.hanglyPlacementBounds(ignoringMenuBar: overlay.anchorsToScreenEdge)

        let frame = ScreenPlacement.frame(
            for: size,
            anchor: overlay.anchor,
            in: bounds,
            offset: CGPoint(x: overlay.horizontalOffset, y: overlay.verticalOffset),
            edgeInset: AppConstants.Overlay.edgeInset
        )

        panel.setFrame(frame, display: true)
        // Re-fit the rope without resetting it, so a scale change swings rather than snaps.
        viewModel.resize(to: frame.size)
    }

    // MARK: - Frame clock

    private func handleTick(_ deltaTime: TimeInterval) {
        viewModel.advance(by: deltaTime)
        // A settled rope needs no frames; the clock still ticks slowly so a grab is
        // still noticed promptly.
        clock.setThrottled(viewModel.isSleeping)
        updateInteractivity()
    }

    /// Decides, every frame, whether the panel should swallow the mouse.
    ///
    /// AppKit cannot pass a click through part of a window and keep the rest, so
    /// click-through is toggled on the whole panel based on where the cursor is.
    /// `NSEvent.mouseLocation` is polled rather than monitored: it needs no event
    /// tap and therefore no Accessibility permission.
    private func updateInteractivity() {
        guard let panel else { return }

        let frame = panel.frame
        let cursor = NSEvent.mouseLocation
        // Screen space is y-up and global; the canvas is y-down and panel-local.
        let local = CGPoint(x: cursor.x - frame.minX, y: frame.maxY - cursor.y)
        // The cursor shape is the whole affordance: nothing is drawn on hover, so a
        // settled rope stays asleep while the pointer crosses it.
        let hovering = viewModel.canGrab(at: local)
        updateCursor(hovering: hovering)

        // Assigning `ignoresMouseEvents` talks to the window server, so only do it
        // when the answer actually changes. Writing it unconditionally every tick
        // is enough to keep a settled overlay measurably busy.
        let shouldIgnore = shouldIgnoreMouseEvents(hovering: hovering)
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }

    private func shouldIgnoreMouseEvents(hovering: Bool) -> Bool {
        // A drag already in progress always keeps the mouse, even if the charm
        // briefly lags behind a fast cursor. So does a file being held over the
        // charm, or a slight drift would cancel the drop.
        if viewModel.isDragging || viewModel.isDropTargeted { return false }
        guard settingsStore.settings.overlay.isClickThrough else { return false }
        return !hovering
    }

    /// An open hand over the charm, a closed hand while holding it. Push and pop
    /// are kept strictly paired so the cursor stack can never be left dirty, and
    /// the cursor is only touched when the wanted cursor actually changes: every
    /// call reaches the window server, and this runs on every frame.
    private func updateCursor(hovering: Bool) {
        let wants = hovering || viewModel.isDragging
        let closed = viewModel.isDragging

        if wants && !cursorIsPushed {
            (closed ? NSCursor.closedHand : NSCursor.openHand).push()
            cursorIsPushed = true
            pushedCursorIsClosedHand = closed
        } else if !wants && cursorIsPushed {
            NSCursor.pop()
            cursorIsPushed = false
        } else if wants && cursorIsPushed && closed != pushedCursorIsClosedHand {
            (closed ? NSCursor.closedHand : NSCursor.openHand).set()
            pushedCursorIsClosedHand = closed
        }
    }

    // MARK: - Panel lifetime

    private func ensurePanel() -> OverlayPanel {
        if let panel { return panel }

        let panel = OverlayPanel(contentRect: CGRect(origin: .zero, size: AppConstants.Overlay.baseSize))

        let hostingView = NSHostingView(rootView: OverlayRootView(viewModel: viewModel))
        hostingView.autoresizingMask = [.width, .height]
        // Belt and braces: the hosting view must not paint an opaque backing, or the
        // panel's transparency is lost.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        self.panel = panel

        // The display link has to come from a view that is in a window, so this must
        // follow `contentView` being set.
        clock.onTick = { [weak self] deltaTime in
            self?.handleTick(deltaTime)
        }
        clock.start(in: hostingView)

        Logger.overlay.diagnostic("Overlay panel created; rope clock running.")
        return panel
    }

    private func teardownPanel() {
        guard let panel else { return }

        if cursorIsPushed {
            NSCursor.pop()
            cursorIsPushed = false
        }
        isFadingOut = false
        clock.stop()
        clock.onTick = nil
        viewModel.stop()

        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
        self.panel = nil
        Logger.overlay.diagnostic("Overlay panel torn down.")
    }
}
