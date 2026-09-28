//
//  HeartCharm.swift
//  Hangly
//

import CoreGraphics

/// A heart, built from four cubic curves meeting at the tip and the centre dip.
struct HeartCharm: BuiltInCharm {
    let kind = CharmKind.heart

    let metrics = CharmMetrics(mass: 2.9, radiusRatio: 0.149, knotInset: 0.68)

    let palette = CharmPalette(
        primary: CharmColor(0.95, 0.27, 0.35),
        secondary: CharmColor(0.78, 0.13, 0.25),
        deep: CharmColor(0.50, 0.06, 0.14),
        light: CharmColor(1.00, 0.72, 0.75)
    )

    func artwork() -> CharmArtwork {
        CharmArtwork(silhouette: heartPath())
    }

    private func heartPath() -> CGPath {
        let path = CGMutablePath()
        let tip = CGPoint(x: 0.5, y: 0.94)
        let dip = CGPoint(x: 0.5, y: 0.26)

        path.move(to: tip)
        // Left flank, sweeping up from the tip to the left lobe.
        path.addCurve(to: CGPoint(x: 0.03, y: 0.35),
                      control1: CGPoint(x: 0.30, y: 0.74),
                      control2: CGPoint(x: 0.03, y: 0.56))
        // Left lobe over the top.
        path.addCurve(to: dip,
                      control1: CGPoint(x: 0.03, y: 0.11),
                      control2: CGPoint(x: 0.34, y: 0.04))
        // Right lobe.
        path.addCurve(to: CGPoint(x: 0.97, y: 0.35),
                      control1: CGPoint(x: 0.66, y: 0.04),
                      control2: CGPoint(x: 0.97, y: 0.11))
        // Right flank back down to the tip.
        path.addCurve(to: tip,
                      control1: CGPoint(x: 0.97, y: 0.56),
                      control2: CGPoint(x: 0.70, y: 0.74))
        path.closeSubpath()
        return path
    }
}
