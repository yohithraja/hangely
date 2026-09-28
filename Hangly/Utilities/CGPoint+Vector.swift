//
//  CGPoint+Vector.swift
//  Hangly
//
//  Minimal 2D vector arithmetic for the rope solver.
//

import CoreGraphics
import Foundation

/// `CGPoint` doubles as the vector type for the simulation.
///
/// Verlet integration constantly mixes positions and displacements, and keeping them
/// in one type avoids a conversion on every line of the solver. These operators are
/// the whole of the maths the rope needs.
extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: CGPoint, rhs: Double) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    static func / (lhs: CGPoint, rhs: Double) -> CGPoint {
        CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    static func += (lhs: inout CGPoint, rhs: CGPoint) {
        lhs = lhs + rhs
    }

    static func -= (lhs: inout CGPoint, rhs: CGPoint) {
        lhs = lhs - rhs
    }

    /// Euclidean length.
    var magnitude: Double {
        (x * x + y * y).squareRoot()
    }

    /// Length without the square root, for comparisons.
    var magnitudeSquared: Double {
        x * x + y * y
    }

    /// Unit vector, or zero for a zero-length vector.
    var normalized: CGPoint {
        let length = magnitude
        guard length > .ulpOfOne else { return .zero }
        return self / length
    }

    func distance(to other: CGPoint) -> Double {
        (other - self).magnitude
    }

    /// Returns the vector rotated counter-clockwise by `radians`.
    func rotated(by radians: Double) -> CGPoint {
        let cosine = cos(radians)
        let sine = sin(radians)
        return CGPoint(x: x * cosine - y * sine, y: x * sine + y * cosine)
    }

    /// Caps the vector's length at `maximum`, preserving direction.
    func limited(to maximum: Double) -> CGPoint {
        let length = magnitude
        guard length > maximum, length > .ulpOfOne else { return self }
        return self * (maximum / length)
    }
}
