//
//  RopeConfiguration.swift
//  Hangly
//
//  Tunable constants for the rope solver.
//

import CoreGraphics
import Foundation

/// Every number the rope solver depends on, in one value type.
///
/// Separating the tuning from the solver keeps `RopeSimulation` free of magic
/// numbers and lets tests drive the solver into deliberately hostile configurations
/// without touching shipped behaviour.
///
/// Units are points and seconds throughout, matching the SwiftUI canvas the rope is
/// drawn into. The canvas has its origin at the top left with `y` increasing
/// downward, so gravity is a **positive** `y` acceleration.
struct RopeConfiguration: Equatable, Sendable {
    /// Number of links. Twenty is the shipped value.
    var segmentCount: Int

    /// Rest length of one link, in points.
    var segmentLength: Double

    /// Downward acceleration in points per second squared.
    var gravity: Double

    /// Fraction of velocity carried into the next step. Below 1 this is air drag:
    /// the rope loses energy and eventually settles instead of swinging forever.
    var damping: Double

    /// Gauss-Seidel relaxation passes per step. More passes means a stiffer rope.
    ///
    /// Corrections propagate roughly one link per pass, so this must exceed
    /// `segmentCount` for a disturbance at the charm to reach the anchor within a
    /// single step. Below that, yanking one end leaves the far end unaware and the
    /// links in between absorb the difference by stretching.
    var constraintIterations: Int

    /// Inequality-projection sweeps applied after relaxation, enforcing the
    /// stretch ceiling on any link relaxation left over its limit.
    var stretchPasses: Int

    /// Relaxation stops early once no link moved further than this in a whole pass.
    /// Both solver loops are capped rather than fixed: a settled rope converges in a
    /// pass or two and exits, so the large caps above cost nothing except in the
    /// rare frame that actually needs them.
    var convergenceTolerance: Double

    /// Hard ceiling on how far a link may exceed its rest length, as a ratio.
    /// Applied after relaxation, so the rope cannot visibly stretch even if the
    /// solver has not fully converged.
    var maxStretchRatio: Double

    /// Physics advances in fixed slices of this length regardless of the display's
    /// refresh rate. This is what makes behaviour identical at 60, 120 and ProMotion's
    /// variable rates, and what keeps Verlet stable.
    var fixedTimeStep: Double

    /// Upper bound on the real time consumed by one frame. Prevents a stall or a
    /// wake-from-sleep from triggering hundreds of catch-up steps at once.
    var maxFrameDuration: Double

    /// Speed ceiling in points per second, applied per node. A safety rail: no
    /// legitimate interaction reaches it, but it makes divergence impossible.
    var maximumSpeed: Double

    /// How far the charm may be dragged from the anchor, as a fraction of the
    /// rope's total length. Below one, so a fully extended rope keeps a little
    /// slack for the solver to work with and never reads as a rigid bar.
    var maximumReachRatio: Double

    /// Node speed, in points per second, below which the rope counts as still.
    var restSpeed: Double

    /// Consecutive still frames before the solver stops working. The rope is a
    /// background ornament, so once it has settled it must stop costing anything;
    /// without this the overlay would redraw at the display rate forever.
    var framesBeforeSleep: Int

    /// Angle from vertical the rope is released at on first appearance, in radians.
    /// A small offset means the rope visibly swings into place instead of being
    /// motionless until touched.
    var initialAngle: Double

    /// Number of nodes, which is one more than the number of links.
    var pointCount: Int {
        segmentCount + 1
    }

    /// Total rest length of the rope.
    var totalLength: Double {
        Double(segmentCount) * segmentLength
    }

    static let `default` = RopeConfiguration(
        segmentCount: 20,
        segmentLength: 11,
        gravity: 2000,
        damping: 0.999,
        constraintIterations: 256,
        stretchPasses: 256,
        convergenceTolerance: 0.05,
        maxStretchRatio: 1.02,
        fixedTimeStep: 1.0 / 240.0,
        maxFrameDuration: 0.1,
        maximumSpeed: 6000,
        maximumReachRatio: 0.98,
        restSpeed: 4.0,
        framesBeforeSleep: 60,
        initialAngle: 0.38
    )

    /// Fits the rope to a canvas, keeping the shipped proportions at any scale.
    /// - Parameter size: The overlay canvas size in points.
    static func fitted(to size: CGSize) -> RopeConfiguration {
        var configuration = RopeConfiguration.default
        let usableLength = max(40, size.height * Layout.lengthFraction)
        configuration.segmentLength = usableLength / Double(configuration.segmentCount)
        return configuration
    }

    /// Proportions shared by the solver and the renderer.
    enum Layout {
        /// Rope length as a fraction of canvas height.
        static let lengthFraction = 0.69

        /// Anchor height as a fraction of canvas height.
        static let anchorFraction = 0.045

        /// Extra radius around the charm that still accepts a grab.
        static let grabPadding = 10.0

        /// Anchor point for a canvas of the given size.
        static func anchor(in size: CGSize) -> CGPoint {
            CGPoint(x: size.width / 2, y: size.height * anchorFraction)
        }
    }
}
