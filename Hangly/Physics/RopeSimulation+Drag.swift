//
//  RopeSimulation+Drag.swift
//  Hangly
//
//  Picking the charm up, moving it and letting it go.
//

import CoreGraphics
import Foundation

/// Dragging, which is input handling rather than physics: it decides what the
/// solver is asked to do with the final node, and the solver decides what the rope
/// does about it.
@MainActor
extension RopeSimulation {
    /// Grabs the charm if `location` is within its grab radius.
    /// - Returns: `true` when the drag was accepted.
    @discardableResult
    func beginDrag(at location: CGPoint) -> Bool {
        guard let index = points.indices.last else { return false }
        guard canGrab(at: location) else { return false }

        dragIndex = index
        dragTarget = location
        dragVelocity = .zero
        wake()
        return true
    }

    /// Whether a grab at `location` would hit the charm.
    func canGrab(at location: CGPoint) -> Bool {
        guard let charm = points.last else { return false }
        let radius = charmRadius + RopeConfiguration.Layout.grabPadding
        return charm.position.distance(to: location) <= radius
    }

    /// - Parameter velocity: Cursor velocity in points per second.
    func updateDrag(to location: CGPoint, velocity: CGPoint) {
        guard dragIndex != nil else { return }
        dragTarget = reachableTarget(for: location)
        dragVelocity = velocity.limited(to: configuration.maximumSpeed)
    }

    /// Pins the drag target to the circle the rope can actually reach.
    ///
    /// Without this, pulling the cursor past the rope's length holds both ends
    /// apart further than the rope can span. The links have nowhere to go but
    /// stretch, and releasing fires the stored tension back as a snap. Clamping
    /// makes the rope go taut and the charm swing around the anchor instead, which
    /// is both what a real cord does and what keeps the stretch bound honest.
    func reachableTarget(for location: CGPoint) -> CGPoint {
        let reach = configuration.totalLength * configuration.maximumReachRatio
        let offset = location - anchor
        let distance = offset.magnitude
        guard distance > reach, distance > .ulpOfOne else { return location }
        return anchor + ((offset / distance) * reach)
    }

    /// Releases the charm. The velocity written during the final step stays in the
    /// node's history, so the rope carries on at the speed it was thrown.
    func endDrag() {
        dragIndex = nil
        dragVelocity = .zero
    }
}
