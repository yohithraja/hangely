//
//  RopeSnapshot.swift
//  Hangly
//
//  Immutable per-frame state handed to the renderer.
//

import CoreGraphics
import Foundation

/// One bead as it should be drawn this frame.
struct BeadPlacement: Equatable, Sendable {
    /// Centre of the bead, on the cord.
    var position: CGPoint

    /// Direction of the cord where it sits, in radians. The bead's artwork is drawn
    /// turned to match, so a bead lies along the cord rather than across it.
    var angle: Double

    /// Drawn size in points.
    var size: CGSize
}

/// Everything the renderer needs for one frame, and nothing it can mutate.
///
/// The solver owns live particle state; the view gets a flat value copy. That split
/// means the render pass cannot perturb the simulation, and it keeps the view
/// testable against hand-written snapshots with no physics running.
struct RopeSnapshot: Equatable, Sendable {
    /// Node positions from the anchor at index zero to the charm at the last index.
    var points: [CGPoint]

    /// Radius of the charm in points.
    var charmRadius: Double

    /// Direction of the final link in radians, used to orient the charm.
    var charmAngle: Double

    /// Where the cord terminates, as a fraction of the charm's radius. Varies by
    /// charm, because a heart meets its cord higher up than a bead does.
    var charmKnotInset: Double

    /// The beads threaded on the cord above the charm, nearest the anchor first.
    var beads: [BeadPlacement]

    /// Longest link as a multiple of its rest length. One means no stretch.
    var maximumStretch: Double

    /// Whether the charm is currently held.
    var isDragging: Bool

    static let empty = RopeSnapshot(
        points: [],
        charmRadius: 0,
        charmAngle: .pi / 2,
        charmKnotInset: 0.9,
        beads: [],
        maximumStretch: 1,
        isDragging: false
    )

    /// Position of the charm, which hangs off the final node.
    var charmCenter: CGPoint {
        points.last ?? .zero
    }

    /// Where the drawn cord stops, which is the knot at the top of the charm.
    var cordEnd: CGPoint {
        let direction = CGPoint(x: cos(charmAngle), y: sin(charmAngle))
        return charmCenter - (direction * (charmRadius * charmKnotInset))
    }

    var anchor: CGPoint {
        points.first ?? .zero
    }
}
