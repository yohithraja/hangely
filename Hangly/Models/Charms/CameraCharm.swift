//
//  CameraCharm.swift
//  Hangly
//

import CoreGraphics

/// A compact camera. The heaviest charm, so it hangs steeper and swings slower.
struct CameraCharm: BuiltInCharm {
    let kind = CharmKind.camera

    let sound = CharmSound.metal

    let metrics = CharmMetrics(mass: 4.2, radiusRatio: 0.170, knotInset: 0.68)

    let palette = CharmPalette(
        primary: CharmColor(0.36, 0.38, 0.43),
        secondary: CharmColor(0.20, 0.22, 0.26),
        deep: CharmColor(0.09, 0.10, 0.12),
        light: CharmColor(0.74, 0.77, 0.82)
    )

    private let lensCentre = CGPoint(x: 0.5, y: 0.58)

    func artwork() -> CharmArtwork {
        // Body and viewfinder bump are one filled silhouette, so they share the
        // shadow, the rim and the highlight rather than reading as two objects.
        let silhouette = CGMutablePath()
        silhouette.addRoundedRect(
            in: CGRect(x: 0.03, y: 0.30, width: 0.94, height: 0.56),
            cornerWidth: 0.13,
            cornerHeight: 0.13
        )
        silhouette.addRoundedRect(
            in: CGRect(x: 0.27, y: 0.18, width: 0.27, height: 0.14),
            cornerWidth: 0.05,
            cornerHeight: 0.05
        )

        return CharmArtwork(silhouette: silhouette, details: [
            CharmDetail(path: circle(radius: 0.205), style: .fill(.deep)),
            CharmDetail(path: circle(radius: 0.150), style: .fill(.secondary)),
            CharmDetail(path: circle(radius: 0.082), style: .fill(.deep)),
            CharmDetail(path: glintPath(), style: .fill(.glint)),
            CharmDetail(path: flashPath(), style: .fill(.light))
        ])
    }

    private func circle(radius: Double) -> CGPath {
        CGPath(
            ellipseIn: CGRect(
                x: lensCentre.x - radius,
                y: lensCentre.y - radius,
                width: radius * 2,
                height: radius * 2
            ),
            transform: nil
        )
    }

    /// Off-centre reflection on the lens glass.
    private func glintPath() -> CGPath {
        CGPath(ellipseIn: CGRect(x: 0.39, y: 0.45, width: 0.10, height: 0.07), transform: nil)
    }

    private func flashPath() -> CGPath {
        CGPath(
            roundedRect: CGRect(x: 0.73, y: 0.37, width: 0.13, height: 0.07),
            cornerWidth: 0.025,
            cornerHeight: 0.025,
            transform: nil
        )
    }
}
