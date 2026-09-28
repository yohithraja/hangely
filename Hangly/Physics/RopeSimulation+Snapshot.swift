//
//  RopeSimulation+Snapshot.swift
//  Hangly
//
//  How the rope reports itself to the renderer.
//

import CoreGraphics
import Foundation

/// Read-only geometry derived from the solver's state.
///
/// Split from the solver so that "how the rope evolves" and "how the rope is
/// measured and drawn" stay separately readable. Nothing here mutates anything;
/// every member is a pure function of the node positions.
extension RopeSimulation {
    var charmRadius: Double {
        configuration.totalLength * charmMetrics.radiusRatio
    }

    /// How the charm hangs: the direction from the knot to the charm's centre.
    ///
    /// Taken from the cord rather than from the final link, so the charm's own loop
    /// lines up with the cord that is drawn into it.
    var charmAngle: Double {
        charmOrientation
    }

    /// Where the charm hangs, which is the last node.
    var charmCenter: CGPoint {
        points.last?.position ?? .zero
    }

    /// Longest link as a multiple of its rest length.
    var measuredMaximumStretch: Double {
        guard configuration.segmentLength > .ulpOfOne, points.count >= 2 else { return 1 }
        var longest = 0.0
        for index in 0..<(points.count - 1) {
            let distance = points[index].position.distance(to: points[index + 1].position)
            longest = max(longest, distance / configuration.segmentLength)
        }
        return longest
    }

    func snapshot() -> RopeSnapshot {
        RopeSnapshot(
            points: points.map(\.position),
            charmRadius: charmRadius,
            charmAngle: charmAngle,
            charmKnotInset: charmMetrics.knotInset,
            beads: beads.map {
                BeadPlacement(position: $0.position, angle: $0.angle, size: $0.size)
            },
            maximumStretch: measuredMaximumStretch,
            isDragging: isDragging
        )
    }
}
