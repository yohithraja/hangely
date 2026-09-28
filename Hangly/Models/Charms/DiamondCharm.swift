//
//  DiamondCharm.swift
//  Hangly
//

import CoreGraphics

/// A cut gem: table, crown and pavilion, with facet lines.
struct DiamondCharm: BuiltInCharm {
    let kind = CharmKind.diamond

    let sound = CharmSound.glass

    let metrics = CharmMetrics(mass: 3.4, radiusRatio: 0.142, knotInset: 0.80)

    let palette = CharmPalette(
        primary: CharmColor(0.62, 0.88, 0.97),
        secondary: CharmColor(0.35, 0.68, 0.88),
        deep: CharmColor(0.18, 0.42, 0.62),
        light: CharmColor(0.90, 0.98, 1.00)
    )

    // Girdle is the widest line across the stone; the table is the flat top.
    private let tableLeft = CGPoint(x: 0.30, y: 0.10)
    private let tableRight = CGPoint(x: 0.70, y: 0.10)
    private let girdleRight = CGPoint(x: 0.96, y: 0.40)
    private let girdleLeft = CGPoint(x: 0.04, y: 0.40)
    private let culet = CGPoint(x: 0.50, y: 0.94)

    func artwork() -> CharmArtwork {
        let silhouette = CGMutablePath()
        silhouette.addLines(between: [tableLeft, tableRight, girdleRight, culet, girdleLeft])
        silhouette.closeSubpath()

        return CharmArtwork(silhouette: silhouette, details: [
            CharmDetail(path: tablePath(), style: .fill(.light)),
            CharmDetail(path: facetPath(), style: .stroke(.light, width: 0.022))
        ])
    }

    /// The bright flat top of the stone.
    private func tablePath() -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [
            tableLeft,
            tableRight,
            CGPoint(x: 0.78, y: 0.40),
            CGPoint(x: 0.22, y: 0.40)
        ])
        path.closeSubpath()
        return path
    }

    /// Girdle plus the two pavilion facets running down to the point.
    private func facetPath() -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [girdleLeft, girdleRight])
        path.move(to: CGPoint(x: 0.22, y: 0.40))
        path.addLine(to: culet)
        path.move(to: CGPoint(x: 0.78, y: 0.40))
        path.addLine(to: culet)
        return path
    }
}
