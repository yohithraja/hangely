//
//  RopeSimulation+Beads.swift
//  Hangly
//
//  The bead pass: particles that ride the cord.
//

import CoreGraphics
import Foundation

/// Beads threaded on the cord above the charm.
///
/// Kept apart from the solver because the dependency runs one way: the rope is
/// solved first and the beads then ride the cord it produced. Nothing here writes a
/// rope node's position, so no amount of bead behaviour can disturb the rope.
@MainActor
extension RopeSimulation {
    /// Fraction of a bead's distance from its rest place taken back per step. The
    /// knot it is threaded against has a little give, not none.
    static let beadTetherStiffness = 0.05

    /// Separation sweeps per step. Beads start apart and move slowly relative to
    /// one another, so two passes are always enough to resolve a touch.
    static let beadSeparationPasses = 2

    /// Advances the beads threaded on the cord.
    ///
    /// Runs after the rope has been solved, so the cord the beads ride on is this
    /// step's cord and not the last one's. Each bead takes a free Verlet step under
    /// gravity and its own momentum, is projected back onto the cord, pulled toward
    /// the knot that holds it and limited to a short slide either side, and finally
    /// separated from its neighbours. The rope never reads the beads back, so none
    /// of this can perturb the rope's own solver.
    func advanceBeads(timeStep: Double) {
        guard !beads.isEmpty, !curve.isEmpty else { return }

        let gravityStep = CGPoint(x: 0, y: configuration.gravity * timeStep * timeStep)
        let damping = configuration.damping
        let displacementLimit = configuration.maximumSpeed * timeStep
        let drawnLength = cordLength

        for index in beads.indices {
            var bead = beads[index]
            let carried = (bead.displacement * damping).limited(to: displacementLimit)
            let predicted = bead.position + carried + gravityStep

            let rest = (drawnLength - bead.restOffset).clamped(to: 0...drawnLength)
            // Search only the cord around where the bead already was: a global
            // search could snap it across a fold in a fast swing.
            let window = bead.slideLimit + bead.spacingRadius + configuration.segmentLength
            var arc = curve.arc(nearestTo: predicted, near: bead.arc, window: window)
            arc += (rest - arc) * Self.beadTetherStiffness
            bead.arc = arc.clamped(to: (rest - bead.slideLimit)...(rest + bead.slideLimit))
            beads[index] = bead
        }

        separateBeads(cordLength: drawnLength)

        for index in beads.indices {
            var bead = beads[index]
            bead.previousPosition = bead.position
            bead.position = curve.point(atArc: bead.arc)
            bead.angle = curve.angle(atArc: bead.arc)
            beads[index] = bead
        }
    }

    /// Pushes touching beads apart along the cord, and keeps the lowest one clear
    /// of the charm and the highest clear of the anchor.
    ///
    /// Resolved from the charm upwards, because that end is a wall: the lowest bead
    /// is placed against it and every bead above gives way in turn. A chain against
    /// one wall settles exactly in a single sweep that way, where splitting each
    /// correction between both beads would leave the last one overlapping whatever
    /// the wall had just pushed it into.
    func separateBeads(cordLength: Double) {
        guard let last = beads.indices.last else { return }

        for _ in 0..<Self.beadSeparationPasses {
            beads[last].arc = min(beads[last].arc, cordLength - beads[last].spacingRadius)
            guard last > 0 else { return }

            for index in stride(from: last - 1, through: 0, by: -1) {
                let minimumGap = beads[index].spacingRadius + beads[index + 1].spacingRadius
                let gap = beads[index + 1].arc - beads[index].arc
                guard gap < minimumGap else { continue }
                beads[index].arc -= minimumGap - gap
            }
            beads[0].arc = max(beads[0].arc, beads[0].spacingRadius)
        }
    }

    /// Re-measures the cord: the curve through the chain, where the charm covers it,
    /// and which way the charm therefore hangs.
    ///
    /// The charm's orientation comes from the cord rather than from the final link.
    /// The two agree on a straight rope and part company on a whipping one, and it
    /// is the cord that has to meet the charm's loop.
    func refreshCord() {
        guard points.count >= 2 else { return }
        curve.rebuild(points: points.map(\.position), end: charmCenter)
        cordLength = curve.arc(enteringCircleAround: charmCenter, radius: knotDistance)
        cordEnd = curve.point(atArc: cordLength)

        let delta = charmCenter - cordEnd
        if delta.magnitudeSquared > .ulpOfOne {
            charmOrientation = atan2(delta.y, delta.x)
        }
    }

    /// How much of the curve the charm's artwork covers, so the cord stops there.
    var knotDistance: Double {
        charmRadius * charmMetrics.knotInset
    }

    /// Re-measures the beads against the charm's current radius.
    /// - Parameter preservingMotion: Keep each bead where it is and let the tether
    ///   carry it to its new place, rather than dropping it there.
    func rebuildBeads(preservingMotion: Bool) {
        let radius = charmRadius
        refreshCord()
        guard !beadDescriptions.isEmpty, radius > 0, points.count >= 2 else {
            beads = []
            applyMasses()
            return
        }

        let drawnLength = curve.isEmpty ? configuration.totalLength - knotDistance : cordLength

        beads = beadDescriptions.enumerated().map { index, description in
            let restOffset = description.offset * radius
            let arc = (drawnLength - restOffset).clamped(to: 0...max(drawnLength, 0))
            let existing = preservingMotion && index < beads.count ? beads[index] : nil
            let position = existing?.position ?? curve.point(atArc: arc)
            return RopeBead(
                position: position,
                previousPosition: existing?.previousPosition ?? position,
                arc: existing?.arc ?? arc,
                restOffset: restOffset,
                spacingRadius: description.spacingRatio * radius,
                size: CGSize(width: description.size.width * radius, height: description.size.height * radius),
                mass: description.mass,
                angle: existing?.angle ?? curve.angle(atArc: arc)
            )
        }
        applyMasses()
    }

    /// Rebuilds every node's inverse mass: the anchor pinned, the charm on the end,
    /// and each bead's weight shared between the two nodes it hangs between.
    ///
    /// Applied when the beads are set rather than on every step. A bead only slides
    /// a few points, so where its weight lands does not meaningfully change as it
    /// moves, and a mass that changed under the solver every step would be a source
    /// of instability for no visible gain.
    func applyMasses() {
        guard let last = points.indices.last, last > 0 else { return }

        for index in points.indices {
            switch index {
            case 0:
                setInverseMass(0, at: index)
            case last:
                setInverseMass(1 / max(charmMetrics.mass, 0.0001), at: index)
            default:
                setInverseMass(1, at: index)
            }
        }

        guard !beads.isEmpty, configuration.segmentLength > .ulpOfOne else { return }
        var load = [Double](repeating: 0, count: points.count)
        for bead in beads {
            let position = (bead.arc / configuration.segmentLength).clamped(to: 0...Double(last))
            let lower = Int(position)
            let upper = min(lower + 1, last)
            let fraction = position - Double(lower)
            load[lower] += bead.mass * (1 - fraction)
            load[upper] += bead.mass * fraction
        }

        for index in 1...last where load[index] > 0 {
            let base = index == last ? charmMetrics.mass : 1
            setInverseMass(1 / max(base + load[index], 0.0001), at: index)
        }
    }
}
