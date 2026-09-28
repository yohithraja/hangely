//
//  RopeSimulation.swift
//  Hangly
//
//  Verlet rope with distance-constraint relaxation.
//

import CoreGraphics
import Foundation

/// A hanging rope simulated with Verlet integration and position-based constraints.
///
/// The step order is deliberate and is what makes the rope both stable and stiff:
///
/// 1. **Pin the anchor.** Done first so a moved anchor drags the rope this step
///    rather than next, which is what makes a window resize look physical.
/// 2. **Integrate.** Each free node moves by its own damped displacement plus
///    gravity. No forces, no velocity array: Verlet infers velocity from history.
/// 3. **Drive the held node.** A dragged node is written directly, with its history
///    set so that its implied velocity matches the cursor's.
/// 4. **Relax constraints.** Gauss-Seidel passes pull each link back to its rest
///    length. Later passes see the corrections of earlier ones, so convergence is
///    fast.
/// 5. **Clamp stretch.** A final hard pass guarantees no link exceeds its limit even
///    if relaxation has not fully converged.
///
/// Time advances in fixed slices. The display's refresh rate only decides how often
/// `step(deltaTime:)` is called, never how far the physics moves per slice, so the
/// rope behaves identically at 60 Hz and 120 Hz.
@MainActor
final class RopeSimulation: PhysicsSimulating {
    private(set) var points: [RopePoint] = []
    private(set) var configuration: RopeConfiguration
    private(set) var anchor: CGPoint

    /// Mass and size contributed by whichever charm is currently attached.
    private(set) var charmMetrics: CharmMetrics

    // The four below are maintained by `RopeSimulation+Beads`, which is the only
    // thing that should write them. They are not `private(set)` only because Swift
    // has no way to say "private to this type across its own files".

    /// The beads threaded on the cord above the charm, nearest the anchor first.
    var beads: [RopeBead] = []

    /// Where the drawn cord stops, which is where the charm's artwork takes over.
    var cordEnd: CGPoint = .zero

    /// Length of the drawn cord, in points. Beads are threaded along it.
    var cordLength: Double = 0

    /// Direction from the knot to the charm's centre, which is how the charm hangs.
    var charmOrientation: Double = .pi / 2

    private(set) var isRunning = false

    /// Fixed steps consumed by the most recent frame. Surfaced in debug mode.
    private(set) var lastStepCount = 0

    /// Whether the rope has settled and stopped simulating. Cleared by `wake()`.
    private(set) var isSleeping = false

    private var stillFrames = 0

    private var accumulator: TimeInterval = 0
    // Written by `RopeSimulation+Drag`, read by the solver.
    var dragIndex: Int?
    var dragTarget: CGPoint = .zero
    var dragVelocity: CGPoint = .zero

    /// What the current charm says its beads are, in proportions.
    var beadDescriptions: [CharmBead] = []

    /// The drawn cord, rebuilt each step and reused rather than reallocated.
    var curve = RopeCurve()

    init(
        configuration: RopeConfiguration = .default,
        anchor: CGPoint = .zero,
        charmMetrics: CharmMetrics = .default
    ) {
        self.configuration = configuration
        self.anchor = anchor
        self.charmMetrics = charmMetrics
        reset()
    }

    /// Attaches a charm's physical properties to the final node.
    ///
    /// Applied in place rather than by rebuilding, so swapping charms keeps the rope
    /// exactly where it was and lets the change interpolate frame by frame.
    func setCharmMetrics(_ metrics: CharmMetrics) {
        guard metrics != charmMetrics else { return }
        charmMetrics = metrics

        // The charm's radius decides where the cord ends and how large the beads
        // are, so they are re-measured — but keep moving, which is what lets a
        // charm change grow its beads into place instead of dropping new ones in.
        rebuildBeads(preservingMotion: true)
        wake()
    }

    /// Attaches the beads the current charm threads onto its cord.
    ///
    /// Beads are described in proportions, so the same description survives a
    /// rescale; the simulation turns them into points against the charm's radius.
    func setBeads(_ descriptions: [CharmBead]) {
        guard descriptions != beadDescriptions else { return }
        beadDescriptions = descriptions
        rebuildBeads(preservingMotion: false)
        wake()
    }

    // MARK: - Derived state

    var isDragging: Bool {
        dragIndex != nil
    }

    // MARK: - PhysicsSimulating

    func start() {
        guard !isRunning else { return }
        if points.isEmpty { reset() }
        accumulator = 0
        isRunning = true
        wake()
    }

    func stop() {
        isRunning = false
        accumulator = 0
    }

    func step(deltaTime: TimeInterval) {
        guard isRunning, deltaTime > 0, !isSleeping else {
            lastStepCount = 0
            return
        }

        // Clamping the accumulator stops a stall or a wake from sleep turning into a
        // burst of catch-up steps, which would look like the rope teleporting.
        accumulator = min(accumulator + deltaTime, configuration.maxFrameDuration)

        let timeStep = configuration.fixedTimeStep
        var taken = 0
        while accumulator >= timeStep {
            advance(timeStep: timeStep)
            accumulator -= timeStep
            taken += 1
        }
        lastStepCount = taken
        updateSleepState()
    }

    /// Wakes the rope so the next `step` does work again.
    func wake() {
        isSleeping = false
        stillFrames = 0
    }

    /// A settled rope is indistinguishable from a still image, so stop drawing one.
    private func updateSleepState() {
        guard dragIndex == nil else {
            stillFrames = 0
            return
        }

        let speedLimit = configuration.restSpeed * configuration.fixedTimeStep
        let moving = points.contains { $0.displacement.magnitude > speedLimit }
            || beads.contains { $0.displacement.magnitude > speedLimit }
        if moving {
            stillFrames = 0
            return
        }

        stillFrames += 1
        if stillFrames >= configuration.framesBeforeSleep {
            isSleeping = true
        }
    }

    func reset() {
        reset(angle: configuration.initialAngle)
    }

    /// Rebuilds the rope hanging straight down with no motion, for users who have
    /// asked for reduced motion: it then moves only when they move it.
    func resetToHanging() {
        reset(angle: 0)
    }

    private func reset(angle: Double) {
        points = RopePoint.chain(configuration: configuration, anchor: anchor, charmMetrics: charmMetrics, angle: angle)
        accumulator = 0
        dragIndex = nil
        dragVelocity = .zero
        lastStepCount = 0
        rebuildBeads(preservingMotion: false)
        wake()
    }

    // MARK: - Geometry changes

    /// Re-fits the rope to a new canvas without discarding its motion, so changing
    /// the overlay scale makes the rope swing rather than snap.
    func resize(to canvasSize: CGSize) {
        let fitted = RopeConfiguration.fitted(to: canvasSize)
        let needsRebuild = points.count != fitted.pointCount

        configuration = fitted
        anchor = RopeConfiguration.Layout.anchor(in: canvasSize)

        if needsRebuild {
            reset()
        } else {
            // The anchor moved, so the rope has somewhere to swing to.
            rebuildBeads(preservingMotion: true)
            wake()
        }
    }

    // MARK: - Solver

    private func advance(timeStep: Double) {
        enforceAnchor()
        integrate(timeStep: timeStep)
        driveDraggedPoint(timeStep: timeStep)

        // Relax until converged, or until the pass budget runs out. Written as a
        // `while` because the exit condition is the point: a `for ... where` would
        // filter iterations rather than end the loop, quietly running the full
        // budget on every step.
        var relaxations = 0
        var residual = Double.infinity
        while relaxations < configuration.constraintIterations,
              residual >= configuration.convergenceTolerance {
            residual = solveDistanceConstraints()
            relaxations += 1
        }

        enforceMaximumStretch()
        refreshCord()
        advanceBeads(timeStep: timeStep)
    }

    private func enforceAnchor() {
        guard !points.isEmpty else { return }
        points[0].position = anchor
        points[0].previousPosition = anchor
    }

    private func integrate(timeStep: Double) {
        let gravityStep = CGPoint(x: 0, y: configuration.gravity * timeStep * timeStep)
        let damping = configuration.damping
        let displacementLimit = configuration.maximumSpeed * timeStep

        for index in points.indices where index != dragIndex {
            guard points[index].inverseMass > 0 else { continue }

            var point = points[index]
            let carried = (point.displacement * damping).limited(to: displacementLimit)
            point.previousPosition = point.position
            point.position += carried + gravityStep
            points[index] = point
        }
    }

    /// Moves the held node toward the cursor, at a finite rate.
    ///
    /// The rate limit matters more than it looks. A held node that teleports leaves
    /// the rest of the chain an unreachable configuration to solve in one step, and
    /// relaxation cannot redistribute that far in the passes available, so links
    /// visibly stretch for a frame. A real cursor cannot teleport, so following at a
    /// bounded speed is the faithful model as well as the stable one. At human
    /// pointer speeds the limit is never reached and tracking is exact.
    private func driveDraggedPoint(timeStep: Double) {
        guard let dragIndex else { return }

        let current = points[dragIndex].position
        let travelLimit = configuration.maximumSpeed * timeStep
        points[dragIndex].position = current + (dragTarget - current).limited(to: travelLimit)
        points[dragIndex].setVelocity(dragVelocity, timeStep: timeStep)
    }

    /// One relaxation pass.
    /// - Returns: The largest correction applied, so the caller can stop early.
    @discardableResult
    private func solveDistanceConstraints() -> Double {
        let restLength = configuration.segmentLength
        var largestCorrection = 0.0
        for index in 0..<(points.count - 1) {
            let correction = solveLink(from: index, to: index + 1, restLength: restLength)
            largestCorrection = max(largestCorrection, correction)
        }
        return largestCorrection
    }

    /// - Returns: The magnitude of the correction applied to this link.
    @discardableResult
    private func solveLink(from indexA: Int, to indexB: Int, restLength: Double) -> Double {
        let inverseA = effectiveInverseMass(at: indexA)
        let inverseB = effectiveInverseMass(at: indexB)
        let totalInverseMass = inverseA + inverseB
        guard totalInverseMass > 0 else { return 0 }

        let delta = points[indexB].position - points[indexA].position
        let distance = delta.magnitude
        guard distance > .ulpOfOne else { return 0 }

        // Split the error between the two nodes in proportion to their mobility.
        let correction = delta * ((distance - restLength) / distance / totalInverseMass)
        points[indexA].position += correction * inverseA
        points[indexB].position -= correction * inverseB
        return max((correction * inverseA).magnitude, (correction * inverseB).magnitude)
    }

    /// The hard guarantee behind "never stretches unrealistically".
    ///
    /// Relaxation targets the rest length and is iterative, so it can leave a link
    /// long after a violent frame. This pass enforces the ceiling as a one-sided
    /// constraint: links inside the limit are untouched, and links over it are
    /// pulled back.
    ///
    /// An earlier version snapped the offending node straight onto the limit. That
    /// oscillated rather than converged, because a chain pinned at both ends had
    /// each sweep undo the last one's work. Splitting the correction between the two
    /// ends, exactly as the distance solver does, converges instead.
    private func enforceMaximumStretch() {
        let limit = configuration.segmentLength * configuration.maxStretchRatio

        for _ in 0..<configuration.stretchPasses {
            var corrected = false
            for index in 0..<(points.count - 1) where clampLink(at: index, limit: limit) {
                corrected = true
            }

            // Converged: every link is inside the limit.
            if !corrected { return }
        }
    }

    /// Pulls one over-long link back to `limit`, sharing the correction between its
    /// ends in proportion to their mobility.
    /// - Returns: Whether the link was over its limit.
    private func clampLink(at index: Int, limit: Double) -> Bool {
        let lower = index
        let upper = index + 1

        let inverseLower = effectiveInverseMass(at: lower)
        let inverseUpper = effectiveInverseMass(at: upper)
        let totalInverseMass = inverseLower + inverseUpper
        guard totalInverseMass > 0 else { return false }

        let delta = points[upper].position - points[lower].position
        let distance = delta.magnitude
        guard distance > limit, distance > .ulpOfOne else { return false }

        let correction = delta * ((distance - limit) / distance / totalInverseMass)
        points[lower].position += correction * inverseLower
        points[upper].position -= correction * inverseUpper
        return true
    }

    /// A held node is immovable for the solver, exactly like the anchor.
    private func effectiveInverseMass(at index: Int) -> Double {
        index == dragIndex ? 0 : points[index].inverseMass
    }

    /// Sets one node's inverse mass.
    ///
    /// The only way anything outside the solver may touch a node, and it exists so
    /// that bead loading can live beside the beads rather than here.
    func setInverseMass(_ value: Double, at index: Int) {
        guard points.indices.contains(index) else { return }
        points[index].inverseMass = value
    }
}
