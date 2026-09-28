//
//  RopeSimulationTests.swift
//  HanglyTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Hangly

/// Exercises the solver directly. The rope is AppKit-free, so every claim about it
/// can be checked numerically rather than by watching the screen.
@Suite("Rope simulation")
@MainActor
struct RopeSimulationTests {
    private let anchor = CGPoint(x: 260, y: 15)
    private let frame120: TimeInterval = 1.0 / 120.0

    private func makeRope() -> RopeSimulation {
        let rope = RopeSimulation(configuration: .default, anchor: anchor)
        rope.start()
        return rope
    }

    /// Advances `seconds` of simulated time in 120 Hz frames.
    private func run(_ rope: RopeSimulation, seconds: TimeInterval) {
        for _ in 0..<Int(seconds / frame120) {
            rope.step(deltaTime: frame120)
        }
    }

    // MARK: - Structure

    @Test("Twenty segments means twenty-one nodes")
    func segmentCountMatchesSpecification() {
        let rope = makeRope()

        #expect(rope.configuration.segmentCount == 20)
        #expect(rope.points.count == 21)
    }

    @Test("The first node is pinned and the charm is the heaviest")
    func massDistributionIsCorrect() {
        let rope = makeRope()

        #expect(rope.points[0].isPinned)
        #expect(rope.points[0].inverseMass == 0)
        // A heavier charm has a smaller inverse mass than a plain node.
        #expect(rope.points[20].inverseMass < rope.points[10].inverseMass)
        #expect(rope.points[10].inverseMass == 1)
    }

    @Test("The anchor never moves, however hard the rope is driven")
    func anchorStaysPinned() {
        let rope = makeRope()
        rope.beginDrag(at: rope.points[20].position)
        rope.updateDrag(to: CGPoint(x: 4000, y: -4000), velocity: CGPoint(x: 9000, y: -9000))
        run(rope, seconds: 2)

        #expect(rope.points[0].position == anchor)
    }

    // MARK: - Inextensibility

    @Test("The rope never stretches beyond its limit at rest")
    func doesNotStretchAtRest() {
        let rope = makeRope()
        run(rope, seconds: 5)

        #expect(rope.measuredMaximumStretch <= rope.configuration.maxStretchRatio + 1e-9)
    }

    @Test("The rope never stretches beyond its limit under a hard flick")
    func doesNotStretchUnderHardFlick() {
        let rope = makeRope()
        run(rope, seconds: 1)
        rope.beginDrag(at: rope.points[20].position)

        // A fast human flick: 3000 points per second, reversing several times a
        // second, and repeatedly yanked well past the rope's reach.
        var position = rope.points[20].position
        var worstStretch = 0.0

        for tick in 0..<1200 {
            let direction: Double = (tick / 18).isMultiple(of: 2) ? 1 : -1
            position += CGPoint(x: direction * 3000 * frame120, y: sin(Double(tick) * 0.05) * 12)
            rope.updateDrag(to: position, velocity: CGPoint(x: direction * 3000, y: 0))
            rope.step(deltaTime: frame120)
            worstStretch = max(worstStretch, rope.measuredMaximumStretch)
        }

        #expect(worstStretch <= rope.configuration.maxStretchRatio + 1e-9)
    }

    @Test("Free swinging produces essentially no stretch")
    func doesNotStretchWhileSwinging() {
        let rope = makeRope()
        run(rope, seconds: 1)

        var worstStretch = 0.0
        for _ in 0..<2400 {
            rope.step(deltaTime: frame120)
            worstStretch = max(worstStretch, rope.measuredMaximumStretch)
        }

        #expect(worstStretch < 1.01)
    }

    @Test("Synthetic torture stays bounded and recovers")
    func recoversFromUnreachableInput() {
        let rope = makeRope()
        run(rope, seconds: 1)
        rope.beginDrag(at: rope.points[20].position)

        // Far beyond anything a pointer can do: nearly seven revolutions a second.
        // Relaxation cannot fully converge inside one frame at this rate, so the
        // guarantee here is that the rope stays bounded rather than exactly at the
        // limit, and snaps back the moment the input stops.
        var worstStretch = 0.0
        for tick in 0..<600 {
            let angle = Double(tick) * 0.35
            let target = anchor + (CGPoint(x: cos(angle), y: sin(angle)) * 900)
            rope.updateDrag(to: target, velocity: CGPoint(x: 6000, y: 6000))
            rope.step(deltaTime: frame120)
            worstStretch = max(worstStretch, rope.measuredMaximumStretch)
        }
        #expect(worstStretch < 1.05)

        rope.endDrag()
        run(rope, seconds: 1)
        #expect(rope.measuredMaximumStretch <= rope.configuration.maxStretchRatio + 1e-9)
    }

    // MARK: - Gravity and damping

    @Test("Gravity swings the rope down below its anchor")
    func gravityPullsTheRopeDown() {
        let rope = makeRope()
        let startX = rope.points[20].position.x
        run(rope, seconds: 20)
        let charm = rope.points[20].position

        // It starts off-vertical by `initialAngle` and must end hanging under the anchor.
        #expect(abs(charm.x - anchor.x) < abs(startX - anchor.x) * 0.25)
        #expect(charm.y > anchor.y + (rope.configuration.totalLength * 0.9))
    }

    @Test("Damping brings the rope to rest")
    func dampingSettlesTheRope() {
        let rope = makeRope()
        run(rope, seconds: 3)
        let movingSpeed = totalSpeed(of: rope)

        run(rope, seconds: 25)
        let settledSpeed = totalSpeed(of: rope)

        #expect(settledSpeed < movingSpeed * 0.1)
    }

    private func totalSpeed(of rope: RopeSimulation) -> Double {
        rope.points.reduce(0) { $0 + $1.displacement.magnitude }
    }

    // MARK: - Frame-rate independence

    @Test("Two 120 Hz frames match one 60 Hz frame exactly")
    func fixedTimeStepMakesRefreshRateIrrelevant() {
        let fast = RopeSimulation(configuration: .default, anchor: anchor)
        let slow = RopeSimulation(configuration: .default, anchor: anchor)
        fast.start()
        slow.start()

        for _ in 0..<120 {
            fast.step(deltaTime: 1.0 / 120.0)
            fast.step(deltaTime: 1.0 / 120.0)
            slow.step(deltaTime: 1.0 / 60.0)
        }

        for index in fast.points.indices {
            #expect(abs(fast.points[index].position.x - slow.points[index].position.x) < 1e-9)
            #expect(abs(fast.points[index].position.y - slow.points[index].position.y) < 1e-9)
        }
    }

    @Test("A long 120 Hz run stays finite and bounded")
    func remainsStableOverALongRun() {
        let rope = makeRope()
        run(rope, seconds: 120)

        let reach = rope.configuration.totalLength * 3
        for point in rope.points {
            #expect(point.position.x.isFinite)
            #expect(point.position.y.isFinite)
            #expect(point.position.distance(to: anchor) < reach)
        }
    }

    @Test("A stalled frame cannot trigger a burst of catch-up steps")
    func clampsOversizedFrames() {
        let rope = makeRope()
        rope.step(deltaTime: 10)

        let ceiling = Int(rope.configuration.maxFrameDuration / rope.configuration.fixedTimeStep) + 1
        #expect(rope.lastStepCount <= ceiling)
    }
}

/// Interaction and lifecycle: grabbing, releasing, resting and resizing.
@Suite("Rope interaction")
@MainActor
struct RopeInteractionTests {
    private let anchor = CGPoint(x: 260, y: 15)
    private let frame120: TimeInterval = 1.0 / 120.0

    private func makeRope() -> RopeSimulation {
        let rope = RopeSimulation(configuration: .default, anchor: anchor)
        rope.start()
        return rope
    }

    private func run(_ rope: RopeSimulation, seconds: TimeInterval) {
        for _ in 0..<Int(seconds / frame120) {
            rope.step(deltaTime: frame120)
        }
    }

    // MARK: - Dragging

    @Test("Only the charm can be grabbed")
    func grabIsLimitedToTheCharm() {
        let rope = makeRope()
        run(rope, seconds: 5)

        #expect(rope.canGrab(at: rope.points[20].position))
        #expect(!rope.canGrab(at: anchor))
        #expect(!rope.canGrab(at: rope.points[10].position))
        #expect(rope.beginDrag(at: anchor) == false)
        #expect(rope.isDragging == false)
    }

    @Test("A held charm settles exactly on the cursor")
    func draggingMovesTheCharmToTheCursor() {
        let rope = makeRope()
        run(rope, seconds: 5)
        rope.beginDrag(at: rope.points[20].position)

        // The held node follows at a bounded speed rather than teleporting, so it
        // takes a few frames to cover a jump this large. At pointer speeds the limit
        // is never reached and tracking is frame-exact.
        let target = CGPoint(x: anchor.x + 120, y: anchor.y + 140)
        for _ in 0..<10 {
            rope.updateDrag(to: target, velocity: .zero)
            rope.step(deltaTime: frame120)
        }

        #expect(rope.points[20].position.distance(to: target) < 1e-6)
    }

    @Test("Releasing the charm preserves its momentum")
    func releasePreservesMomentum() {
        let rope = makeRope()
        run(rope, seconds: 5)
        rope.beginDrag(at: rope.points[20].position)

        // Sweep along the arc the rope can actually reach, so the motion is a real
        // swing rather than a stretched cord waiting to snap back.
        let radius = rope.configuration.totalLength * 0.9
        let speed = 900.0
        let angularStep = (speed / radius) * frame120
        var angle = Double.pi / 2

        for _ in 0..<16 {
            angle -= angularStep
            let target = anchor + (CGPoint(x: cos(angle), y: sin(angle)) * radius)
            let tangent = CGPoint(x: sin(angle), y: -cos(angle)) * speed
            rope.updateDrag(to: target, velocity: tangent)
            rope.step(deltaTime: frame120)
        }

        let held = rope.points[20].displacement / frame120
        rope.endDrag()
        rope.step(deltaTime: frame120)
        let released = rope.points[20].displacement / frame120

        // It must keep most of its speed, and keep going the same way.
        #expect(released.magnitude > held.magnitude * 0.5)
        #expect((released.x * held.x) + (released.y * held.y) > 0)
        #expect(released.x > 0)
    }

    @Test("Releasing a stationary charm adds no momentum")
    func releaseWithoutMotionDoesNotLaunchTheCharm() {
        let rope = makeRope()
        run(rope, seconds: 5)
        rope.beginDrag(at: rope.points[20].position)

        // Held still, well inside the rope's reach.
        let held = anchor + (CGPoint(x: 0.6, y: 0.8) * (rope.configuration.totalLength * 0.9))
        for _ in 0..<60 {
            rope.updateDrag(to: held, velocity: .zero)
            rope.step(deltaTime: frame120)
        }
        rope.endDrag()
        rope.step(deltaTime: frame120)

        // It should begin falling under gravity, not shoot sideways.
        let speed = rope.points[20].displacement.magnitude / frame120
        #expect(speed < 200)
    }

    // MARK: - Idling

    @Test("The rope stops simulating once it has settled")
    func sleepsWhenSettled() {
        let rope = makeRope()
        #expect(rope.isSleeping == false)

        run(rope, seconds: 40)

        #expect(rope.isSleeping)
        #expect(rope.lastStepCount == 0)
    }

    @Test("A settled rope stays exactly where it stopped")
    func sleepingRopeDoesNotDrift() {
        let rope = makeRope()
        run(rope, seconds: 40)
        let resting = rope.points.map(\.position)

        run(rope, seconds: 20)

        for (index, position) in rope.points.map(\.position).enumerated() {
            #expect(position == resting[index])
        }
    }

    @Test("Grabbing the charm wakes the rope")
    func draggingWakesTheRope() {
        let rope = makeRope()
        run(rope, seconds: 40)
        #expect(rope.isSleeping)

        rope.beginDrag(at: rope.points[20].position)

        #expect(rope.isSleeping == false)
        rope.updateDrag(to: rope.points[20].position + CGPoint(x: 40, y: 0), velocity: CGPoint(x: 400, y: 0))
        rope.step(deltaTime: frame120)
        #expect(rope.lastStepCount > 0)
    }

    @Test("Moving the anchor wakes the rope")
    func resizingWakesTheRope() {
        let rope = makeRope()
        run(rope, seconds: 40)
        #expect(rope.isSleeping)

        rope.resize(to: CGSize(width: 700, height: 300))

        #expect(rope.isSleeping == false)
    }

    // MARK: - Reduce Motion

    @Test("The rest pose hangs straight down with no motion")
    func restPoseIsStill() {
        let rope = makeRope()
        rope.resetToHanging()

        for point in rope.points {
            #expect(abs(point.position.x - anchor.x) < 1e-9)
            #expect(point.displacement.magnitude < 1e-9)
        }
        #expect(rope.points[20].position.y > anchor.y + (rope.configuration.totalLength * 0.99))

        // It stays put and goes to sleep on its own.
        run(rope, seconds: 2)
        #expect(rope.isSleeping)
        #expect(abs(rope.points[20].position.x - anchor.x) < 0.01)
    }

    // MARK: - Resizing

    @Test("Resizing re-anchors and re-fits without destroying motion")
    func resizingKeepsTheRopeAlive() {
        let rope = makeRope()
        run(rope, seconds: 1)

        rope.resize(to: CGSize(width: 1040, height: 600))

        #expect(rope.anchor.x == 520)
        #expect(rope.points.count == 21)
        #expect(rope.configuration.segmentCount == 20)

        run(rope, seconds: 3)
        #expect(rope.measuredMaximumStretch <= rope.configuration.maxStretchRatio + 1e-9)
    }
}
