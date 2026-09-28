//
//  OverlayViewModel.swift
//  Hangly
//
//  Presentation state for the overlay content.
//

import CoreGraphics
import Foundation
import Observation
import OSLog

/// Drives `OverlayRootView`.
///
/// Owns the rope simulation and republishes it to the view as an immutable
/// `RopeSnapshot` once per frame. Exactly one observable write happens per frame,
/// which is what keeps SwiftUI invalidation proportional to the display rate rather
/// than to the number of nodes.
///
/// It also owns the charm change: it notices a new selection on the next frame,
/// cross-fades the artwork and interpolates the charm's mass and size into the
/// simulation, so switching is live and never jumps.
///
/// Window size and screen position stay with `OverlayWindowController`.
@MainActor
@Observable
final class OverlayViewModel {
    /// The current frame, read by the renderer.
    private(set) var snapshot: RopeSnapshot = .empty

    /// The charm or charms to draw this frame.
    private(set) var charmLayers: [CharmLayer] = []

    #if !HANGLY_PRODUCTION
    /// Whether the debug overlay is drawn. See `AppConstants.Debug`.
    private(set) var isDebugEnabled = false

    /// Pre-rendered debug text, refreshed a few times a second rather than every
    /// frame so the canvas can reuse its resolved text between updates.
    private(set) var debugSummary = ""
    #endif

    /// A file is being held over the charm.
    private(set) var isDropTargeted = false

    /// Angle of the progress arc while an import runs; `nil` when idle.
    private(set) var importSpinnerAngle: Double?

    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let charmManager: CharmManager
    @ObservationIgnored private let importCoordinator: CharmImportCoordinator
    @ObservationIgnored private let audio: AudioService
    @ObservationIgnored private let accessibility: AccessibilityPreferences
    @ObservationIgnored private let simulation: RopeSimulation

    @ObservationIgnored private var activeCharm: any Charm
    @ObservationIgnored private var activeArtwork: CharmArtwork

    /// Resolved once per charm change. A vector charm measures its own artwork to
    /// find where its cord ends, so this is worth holding rather than re-reading on
    /// every frame of a transition.
    @ObservationIgnored private var activeMetrics: CharmMetrics
    @ObservationIgnored private var outgoingCharm: (any Charm)?
    @ObservationIgnored private var outgoingArtwork: CharmArtwork?
    @ObservationIgnored private var transitionStart: CharmMetrics
    @ObservationIgnored private var transitionProgress: Double = 1

    /// A release slower than this is a placement, not a swing, and makes no sound.
    private static let soundSpeedThreshold = 500.0

    /// Speed at which a swing reaches full volume.
    private static let soundFullSpeed = 2600.0

    @ObservationIgnored private var elapsed: TimeInterval = 0
    #if !HANGLY_PRODUCTION
    @ObservationIgnored private var nextDebugRefresh: TimeInterval = 0
    @ObservationIgnored private var smoothedFrameRate: Double = 0
    #endif

    #if !HANGLY_PRODUCTION
    /// How often the debug read-out is recomputed, in seconds.
    private static let debugRefreshInterval: TimeInterval = 0.2
    #endif

    /// Long enough to read as a deliberate change, short enough not to feel slow.
    private static let charmTransitionDuration: TimeInterval = 0.28

    init(
        settingsStore: SettingsStore,
        charmManager: CharmManager,
        importCoordinator: CharmImportCoordinator,
        audio: AudioService,
        accessibility: AccessibilityPreferences,
        simulation: RopeSimulation = RopeSimulation()
    ) {
        self.settingsStore = settingsStore
        self.charmManager = charmManager
        self.importCoordinator = importCoordinator
        self.audio = audio
        self.accessibility = accessibility
        self.simulation = simulation

        let charm = charmManager.current
        self.activeCharm = charm
        self.activeArtwork = charm.hangingArtwork()
        self.activeMetrics = charm.metrics
        self.transitionStart = charm.metrics
    }

    /// Alpha applied to the rendered content.
    var opacity: Double {
        settingsStore.settings.overlay.opacity
    }

    var isDragging: Bool {
        simulation.isDragging
    }

    /// Whether the rope has settled. The clock drops to a low rate when it has.
    var isSleeping: Bool {
        simulation.isSleeping
    }

    /// Extra radius around the charm that still accepts a grab.
    var grabRadius: Double {
        snapshot.charmRadius + RopeConfiguration.Layout.grabPadding
    }

    // MARK: - Lifecycle

    func start() {
        simulation.setCharmMetrics(activeMetrics)
        simulation.setBeads(activeCharm.beads)
        simulation.start()
        // With Reduce Motion on, nothing moves until the user moves it.
        if accessibility.reducesMotion {
            simulation.resetToHanging()
        }
        snapshot = simulation.snapshot()
        updateCharmLayers(progress: 1)
    }

    func stop() {
        simulation.stop()
    }

    /// Re-fits the rope when the overlay's canvas changes size.
    func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        simulation.resize(to: size)
        snapshot = simulation.snapshot()
    }

    /// Advances the simulation by one display frame.
    ///
    /// While the rope sleeps no snapshot is published, so Observation never fires
    /// and SwiftUI never redraws. That is what takes a settled overlay down to
    /// nothing: the canvas is only asked to draw when something has actually moved.
    func advance(by deltaTime: TimeInterval) {
        elapsed += deltaTime
        syncCharmSelection()
        advanceCharmTransition(by: deltaTime)
        updateImportIndicator()

        let wasSleeping = simulation.isSleeping
        simulation.step(deltaTime: deltaTime)

        // Publish while awake, plus once more on the frame it falls asleep so the
        // final resting pose is drawn.
        if !simulation.isSleeping || !wasSleeping {
            snapshot = simulation.snapshot()
        }
        if simulation.isSleeping != wasSleeping {
            Logger.overlay.diagnostic("Rope \(self.simulation.isSleeping ? "asleep" : "awake").")
        }

        #if !HANGLY_PRODUCTION
        refreshDebugState(deltaTime: deltaTime)
        #endif
    }

    // MARK: - Interaction

    /// Whether a press at `location` would land on the charm.
    func canGrab(at location: CGPoint) -> Bool {
        simulation.canGrab(at: location)
    }

    func dragChanged(location: CGPoint, velocity: CGPoint) {
        if !simulation.isDragging {
            simulation.beginDrag(at: location)
        }
        simulation.updateDrag(to: location, velocity: velocity)
    }

    /// Releasing hands the cursor's final velocity to the charm, so the rope keeps
    /// travelling instead of stopping dead. A real swing also makes the charm's sound.
    func dragEnded(location: CGPoint, velocity: CGPoint) {
        guard simulation.isDragging else { return }
        simulation.updateDrag(to: location, velocity: velocity)
        simulation.endDrag()

        let speed = velocity.magnitude
        if speed > Self.soundSpeedThreshold {
            let intensity = ((speed - Self.soundSpeedThreshold) / Self.soundFullSpeed).clamped(to: 0.25...1)
            audio.play(activeCharm.sound, intensity: intensity)
        }
    }

    // MARK: - Importing by drop

    func setDropTargeted(_ targeted: Bool) {
        guard targeted != isDropTargeted else { return }
        isDropTargeted = targeted
    }

    /// Opens the first supported dropped file in the Studio.
    /// - Returns: Whether the drop was accepted.
    func handleDrop(_ urls: [URL]) -> Bool {
        setDropTargeted(false)
        guard let url = urls.first(where: CharmImageProcessor.isSupported) else { return false }
        return importCoordinator.presentStudio(with: url)
    }

    /// Keeps frames flowing and the arc turning while an import runs, and stops
    /// publishing the moment it finishes so the rope can go back to sleep.
    private func updateImportIndicator() {
        if charmManager.isImporting {
            simulation.wake()
            importSpinnerAngle = (elapsed * 4.5).truncatingRemainder(dividingBy: 2 * .pi)
        } else if importSpinnerAngle != nil {
            importSpinnerAngle = nil
        }
    }

    // MARK: - Charm changes

    /// Picks up a new selection on the next frame. Polling rather than observing
    /// keeps the change on the same clock as the animation that follows it.
    private func syncCharmSelection() {
        let selected = charmManager.selection
        guard selected != activeCharm.id else { return }

        outgoingCharm = activeCharm
        outgoingArtwork = activeArtwork
        activeCharm = charmManager.charm(for: selected)
        activeArtwork = activeCharm.hangingArtwork()
        activeMetrics = activeCharm.metrics
        // The incoming charm's beads take over the cord at once and fade in with
        // it; the outgoing charm's artwork is drawn on them until it is gone.
        simulation.setBeads(activeCharm.beads)
        // Start from where the rope actually is, not from the outgoing charm's
        // nominal size, so interrupting a change mid-way still looks continuous.
        transitionStart = simulation.charmMetrics
        transitionProgress = 0
        simulation.wake()
        audio.play(activeCharm.sound, intensity: 0.6)

        // Reduce Motion: no cross-fade, the new charm is simply there.
        if accessibility.reducesMotion {
            transitionProgress = 1
            simulation.setCharmMetrics(activeMetrics)
            outgoingCharm = nil
            outgoingArtwork = nil
            updateCharmLayers(progress: 1)
        }
    }

    private func advanceCharmTransition(by deltaTime: TimeInterval) {
        guard transitionProgress < 1 else { return }

        transitionProgress = min(1, transitionProgress + (deltaTime / Self.charmTransitionDuration))
        let eased = Self.smoothStep(transitionProgress)

        // Mass and radius move together with the artwork, so the grab region and the
        // swing weight always match what is on screen.
        simulation.setCharmMetrics(
            CharmMetrics.interpolate(from: transitionStart, to: activeMetrics, progress: eased)
        )
        updateCharmLayers(progress: eased)

        if transitionProgress >= 1 {
            outgoingCharm = nil
            outgoingArtwork = nil
        }
    }

    private func updateCharmLayers(progress: Double) {
        var layers: [CharmLayer] = []

        if let outgoing = outgoingCharm, progress < 1 {
            // Shrinking as it leaves keeps the dissolve readable; two shapes at the
            // same size and half opacity just look like one muddled shape.
            layers.append(CharmLayer(
                charm: outgoing,
                artwork: outgoingArtwork,
                opacity: 1 - progress,
                scale: 1 - (0.12 * progress)
            ))
        }
        layers.append(CharmLayer(
            charm: activeCharm,
            artwork: activeArtwork,
            opacity: progress,
            scale: 0.92 + (0.08 * progress)
        ))

        charmLayers = layers
    }

    /// Ease in and out, so the change starts and finishes gently.
    private static func smoothStep(_ value: Double) -> Double {
        let clamped = value.clamped(to: 0...1)
        return clamped * clamped * (3 - (2 * clamped))
    }

    // MARK: - Debug

    // Development only. The refresh below reads `UserDefaults` five times a second
    // for as long as the rope is awake, which is not a cost a shipped ornament
    // should carry, so all of it is compiled out of production builds.
    #if !HANGLY_PRODUCTION
    private func refreshDebugState(deltaTime: TimeInterval) {
        if deltaTime > 0 {
            let instantaneous = 1 / deltaTime
            smoothedFrameRate = smoothedFrameRate == 0
                ? instantaneous
                : (smoothedFrameRate * 0.9) + (instantaneous * 0.1)
        }

        guard elapsed >= nextDebugRefresh else { return }
        nextDebugRefresh = elapsed + Self.debugRefreshInterval

        // Re-read each refresh so `defaults write` takes effect without a relaunch.
        let enabled = UserDefaults.standard.bool(forKey: AppConstants.Debug.ropeOverlayKey)
        if enabled != isDebugEnabled {
            isDebugEnabled = enabled
        }

        // Assign only on change: an unconditional write would invalidate the view
        // several times a second even with the rope asleep and debug off.
        let summary = enabled ? makeDebugSummary() : ""
        if summary != debugSummary {
            debugSummary = summary
        }
    }

    private func makeDebugSummary() -> String {
        let configuration = simulation.configuration
        let metrics = simulation.charmMetrics
        let stretchPercent = max(0, (snapshot.maximumStretch - 1) * 100)
        let solverHertz = Int((1 / configuration.fixedTimeStep).rounded())

        return """
        HANGLY ROPE DEBUG
        nodes       \(snapshot.points.count) (\(configuration.segmentCount) segments)
        display     \(Int(smoothedFrameRate.rounded())) fps
        solver      \(simulation.lastStepCount) steps/frame @ \(solverHertz) Hz
        iterations  \(configuration.constraintIterations)
        max stretch +\(String(format: "%.2f", stretchPercent))%
        charm       \(activeCharm.displayName) m=\(String(format: "%.2f", metrics.mass))
        beads       \(snapshot.beads.count) on \(String(format: "%.0f", simulation.cordLength)) pt of cord
        dragging    \(simulation.isDragging ? "yes" : "no")
        state       \(simulation.isSleeping ? "asleep" : "running")
        """
    }
    #endif
}
