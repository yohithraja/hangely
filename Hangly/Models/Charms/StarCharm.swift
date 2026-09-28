//
//  StarCharm.swift
//  Hangly
//

import CoreGraphics
import Foundation

/// A five-pointed star. The lightest charm, so it swings fastest.
struct StarCharm: BuiltInCharm {
    let kind = CharmKind.star

    let metrics = CharmMetrics(mass: 2.2, radiusRatio: 0.157, knotInset: 0.90)

    let palette = CharmPalette(
        primary: CharmColor(1.00, 0.78, 0.25),
        secondary: CharmColor(0.93, 0.58, 0.10),
        deep: CharmColor(0.62, 0.35, 0.03),
        light: CharmColor(1.00, 0.93, 0.70)
    )

    private let centre = CGPoint(x: 0.5, y: 0.52)
    private let outerRadius = 0.48
    private let innerRadius = 0.205

    func artwork() -> CharmArtwork {
        CharmArtwork(silhouette: starPath(scale: 1), details: [
            // A smaller star inset as a facet, which catches the highlight.
            CharmDetail(path: starPath(scale: 0.56), style: .fill(.light))
        ])
    }

    /// Ten alternating vertices, starting at the top point.
    private func starPath(scale: Double) -> CGPath {
        let path = CGMutablePath()
        let points = (0..<10).map { index -> CGPoint in
            let angle = (-Double.pi / 2) + (Double(index) * .pi / 5)
            let radius = (index.isMultiple(of: 2) ? outerRadius : innerRadius) * scale
            return CGPoint(x: centre.x + (cos(angle) * radius), y: centre.y + (sin(angle) * radius))
        }
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }
}
