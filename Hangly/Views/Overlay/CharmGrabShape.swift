//
//  CharmGrabShape.swift
//  Hangly
//
//  Hit region for grabbing the charm.
//

import SwiftUI

/// The only part of the overlay that accepts the mouse.
///
/// Used as the canvas's `contentShape`, so SwiftUI hit-tests a disc around the charm
/// and ignores every other pixel. That keeps the overlay click-through everywhere
/// the rope is not, which is the Phase 1 behaviour the charm has to coexist with.
struct CharmGrabShape: Shape {
    let center: CGPoint
    let radius: Double

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}
