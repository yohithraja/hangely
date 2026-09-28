//
//  RopeBeadTests.swift
//  HanglyTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Hangly

/// Beads hang on the cord above the charm and are simulated, not painted on.
///
/// The claims worth holding are all geometric, so they can be checked numerically
/// against a running solver rather than by looking at the screen: beads sit on the
/// cord, keep out of each other and out of the charm, move when the rope moves, and
/// never wander away from where the artwork drew them.
@Suite("Rope beads")
@MainActor
struct RopeBeadTests {
    private let size = AppConstants.Overlay.baseSize
    private let frame120: TimeInterval = 1.0 / 120.0

    private func makeRope(_ kind: CharmKind = .daruma) -> (RopeSimulation, any Charm) {
        let charm = BuiltInCharms.charm(for: kind)
        let rope = RopeSimulation(
            configuration: .fitted(to: size),
            anchor: RopeConfiguration.Layout.anchor(in: size),
            charmMetrics: charm.metrics
        )
        rope.start()
        rope.setCharmMetrics(charm.metrics)
        rope.setBeads(charm.beads)
        return (rope, charm)
    }

    private func run(_ rope: RopeSimulation, seconds: TimeInterval) {
        for _ in 0..<Int(seconds / frame120) {
            rope.step(deltaTime: frame120)
        }
    }

    /// Drags the charm in a wide arc and lets go, which is the worst a user can do.
    private func shake(_ rope: RopeSimulation, cycles: Int = 6) {
        rope.beginDrag(at: rope.points[20].position)
        var angle = Double.pi / 2
        let radius = rope.configuration.totalLength * 0.9
        for tick in 0..<(cycles * 60) {
            angle += (tick / 30).isMultiple(of: 2) ? 0.08 : -0.08
            let target = rope.anchor + (CGPoint(x: cos(angle), y: sin(angle)) * radius)
            rope.updateDrag(to: target, velocity: CGPoint(x: 2200, y: 1200))
            rope.step(deltaTime: frame120)
        }
        rope.endDrag()
    }

    private func curve(_ rope: RopeSimulation) -> RopeCurve {
        RopeCurve(points: rope.points.map(\.position), end: rope.points[20].position)
    }

    // MARK: - Placement

    @Test("The collection's charms bring beads, and they are laid out as drawn")
    func beadsComeFromTheArtwork() throws {
        let charm = BuiltInCharms.charm(for: .daruma)
        #expect(charm.beads.count == 3)

        // Ordered from the anchor down, so each sits nearer the charm than the last.
        var previous = Double.infinity
        for bead in charm.beads {
            #expect(bead.offset > 0, "a bead must sit above the knot")
            #expect(bead.offset < previous)
            #expect(bead.size.width > 0)
            #expect(bead.size.height > 0)
            #expect(bead.mass > 0)
            previous = bead.offset
        }

        // A charm the artwork draws on a bare cord brings none.
        #expect(BuiltInCharms.charm(for: .himmeli).beads.isEmpty)
        // Neither do the classics, which are geometry rather than artwork.
        #expect(BuiltInCharms.charm(for: .circle).beads.isEmpty)
    }

    @Test("Beads sit on the cord, above the charm")
    func beadsSitOnTheCord() {
        let (rope, _) = makeRope()
        run(rope, seconds: 4)
        let line = curve(rope)

        #expect(rope.beads.count == 3)
        for bead in rope.beads {
            let arc = line.arc(nearestTo: bead.position, near: bead.arc, window: 200)
            #expect(line.point(atArc: arc).distance(to: bead.position) < 0.5)
            #expect(bead.arc <= rope.cordLength + 0.001, "a bead must not pass the knot")
            #expect(bead.position.distance(to: rope.points[20].position) > rope.charmRadius * 0.9)
        }
    }

    @Test("Beads keep their spacing however hard the rope is shaken")
    func beadsNeverOverlap() {
        let (rope, _) = makeRope()
        run(rope, seconds: 1)

        var worstOverlap = 0.0
        for _ in 0..<6 {
            shake(rope, cycles: 1)
            for index in 0..<(rope.beads.count - 1) {
                let gap = rope.beads[index + 1].arc - rope.beads[index].arc
                let needed = rope.beads[index].spacingRadius + rope.beads[index + 1].spacingRadius
                worstOverlap = max(worstOverlap, needed - gap)
            }
            // And never into the charm.
            let last = rope.beads[rope.beads.count - 1]
            worstOverlap = max(worstOverlap, (last.arc + last.spacingRadius) - rope.cordLength)
        }
        #expect(worstOverlap < 0.001)
    }

    @Test("Beads slide during motion and return to where they were drawn")
    func beadsSlideButDoNotMigrate() {
        let (rope, _) = makeRope()
        run(rope, seconds: 4)
        let resting = rope.beads.map(\.arc)

        // Measured from the knot rather than from the anchor: a bending rope
        // shortens the cord a little, and that is the cord's business, not a slide.
        func slide(_ bead: RopeBead) -> Double {
            abs((rope.cordLength - bead.arc) - bead.restOffset)
        }

        var largestSlide = 0.0
        rope.beginDrag(at: rope.points[20].position)
        for tick in 0..<240 {
            let target = rope.anchor + CGPoint(x: sin(Double(tick) * 0.25) * 240, y: 210)
            rope.updateDrag(to: target, velocity: CGPoint(x: 2600, y: 0))
            rope.step(deltaTime: frame120)
            for bead in rope.beads {
                largestSlide = max(largestSlide, slide(bead))
                // The tether bounds the slide; separation can add at most a
                // neighbour's push on top of it, and nothing else may.
                #expect(slide(bead) <= bead.slideLimit + bead.spacingRadius)
            }
        }
        rope.endDrag()

        // It has to be visible motion, not a number that only exists in the solver.
        #expect(largestSlide > 0.5)

        run(rope, seconds: 20)
        for (index, bead) in rope.beads.enumerated() {
            #expect(abs(bead.arc - resting[index]) < 2, "bead \(index) drifted")
        }
    }

    @Test("Beads move when the rope moves")
    func beadsFollowTheRope() {
        let (rope, _) = makeRope()
        run(rope, seconds: 4)
        let before = rope.beads.map(\.position)

        rope.beginDrag(at: rope.points[20].position)
        let target = rope.anchor + CGPoint(x: 220, y: 180)
        for _ in 0..<60 {
            rope.updateDrag(to: target, velocity: CGPoint(x: 1800, y: 0))
            rope.step(deltaTime: frame120)
        }

        for (index, bead) in rope.beads.enumerated() {
            #expect(bead.position.distance(to: before[index]) > 10, "bead \(index) did not travel")
        }
    }

    // MARK: - Effect on the rope

    @Test("Beads put their weight on the cord")
    func beadsLoadTheRope() {
        let charm = BuiltInCharms.charm(for: .daruma)
        let bare = RopeSimulation(
            configuration: .fitted(to: size),
            anchor: RopeConfiguration.Layout.anchor(in: size),
            charmMetrics: charm.metrics
        )
        bare.start()
        let (loaded, _) = makeRope()

        let lightened = zip(bare.points, loaded.points).filter { $0.inverseMass > $1.inverseMass }
        #expect(!lightened.isEmpty, "a bead's mass has to land somewhere")
        // And only in the stretch of rope the beads occupy.
        for (index, point) in loaded.points.enumerated() where index < 10 {
            #expect(point.inverseMass == bare.points[index].inverseMass)
        }
    }

    @Test("A rope carrying beads is as inextensible and as quiet as one without")
    func beadsDoNotDisturbTheRope() {
        let (rope, _) = makeRope()
        run(rope, seconds: 1)

        var worstStretch = 0.0
        shake(rope, cycles: 4)
        for _ in 0..<1200 {
            rope.step(deltaTime: frame120)
            worstStretch = max(worstStretch, rope.measuredMaximumStretch)
        }
        #expect(worstStretch <= rope.configuration.maxStretchRatio + 1e-9)

        for bead in rope.beads {
            #expect(bead.position.x.isFinite)
            #expect(bead.position.y.isFinite)
        }

        run(rope, seconds: 40)
        #expect(rope.isSleeping, "beads must not keep the overlay awake")
    }

    @Test("Two 120 Hz frames match one 60 Hz frame, beads included")
    func beadsAreFrameRateIndependent() {
        let (fast, _) = makeRope()
        let (slow, _) = makeRope()

        for _ in 0..<120 {
            fast.step(deltaTime: 1.0 / 120.0)
            fast.step(deltaTime: 1.0 / 120.0)
            slow.step(deltaTime: 1.0 / 60.0)
        }

        for index in fast.beads.indices {
            #expect(abs(fast.beads[index].arc - slow.beads[index].arc) < 1e-9)
        }
    }

    @Test("Changing charm changes the beads on the cord")
    func beadsFollowTheCharm() {
        let (rope, _) = makeRope(.daruma)
        run(rope, seconds: 2)
        #expect(rope.beads.count == 3)

        let himmeli = BuiltInCharms.charm(for: .himmeli)
        rope.setCharmMetrics(himmeli.metrics)
        rope.setBeads(himmeli.beads)
        #expect(rope.beads.isEmpty)

        let ghanta = BuiltInCharms.charm(for: .ghanta)
        rope.setCharmMetrics(ghanta.metrics)
        rope.setBeads(ghanta.beads)
        run(rope, seconds: 2)
        #expect(rope.beads.count == ghanta.beads.count)
        #expect(rope.beads[0].arc <= rope.cordLength)
    }

    // MARK: - Scaling

    @Test("Beads keep their proportions when the overlay is resized")
    func beadsScaleWithTheOverlay() {
        let (rope, _) = makeRope()
        run(rope, seconds: 3)
        let before = rope.beads.map { $0.size.height / rope.charmRadius }

        rope.resize(to: CGSize(width: size.width * 1.5, height: size.height * 1.5))
        run(rope, seconds: 3)
        let after = rope.beads.map { $0.size.height / rope.charmRadius }

        #expect(before.count == after.count)
        for (old, new) in zip(before, after) {
            #expect(abs(old - new) < 1e-9)
        }
        #expect(rope.beads[0].arc <= rope.cordLength)
    }
}
