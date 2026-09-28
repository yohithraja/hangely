//
//  MenuBarIconArtwork.swift
//  Hangly
//
//  The drawn status item image.
//

import AppKit
import CoreGraphics

/// Draws the status item: a nazar on its beaded cord, in outline.
///
/// A template image, so AppKit owns its colour: it inverts with the menu bar's
/// appearance, dims when the app is in the background and highlights when the menu
/// is open, none of which a coloured bitmap would do. Drawn from geometry rather
/// than shipped as a bitmap so it is exact at every scale factor and menu bar size.
///
/// The proportions are the supplied artwork's. Its line weight is not: the original
/// draws hairlines about a sixtieth of the charm's width, which at eighteen points
/// is a tenth of a pixel. Everything here is stroked at a weight that survives the
/// menu bar instead, and the eye carries one ring inside its rim rather than the
/// original's two — at this size a second ring closes the gap to its neighbours and
/// the whole eye reads as a smudge.
///
/// Both states are drawn once and kept, since the view body is re-evaluated far more
/// often than the state changes.
enum MenuBarIconArtwork {
    /// The standard status item square.
    static let side: CGFloat = 18

    private static let showing = render(showing: true)
    private static let hidden = render(showing: false)

    static func image(showing isShowing: Bool) -> NSImage {
        isShowing ? showing : hidden
    }

    // MARK: - Geometry

    /// Measured from the artwork, in units of the charm's radius, with the origin at
    /// the charm's centre and `y` growing downward.
    private enum Artwork {
        /// The charm body.
        static let bodyRadius: CGFloat = 1

        /// The ring inside the rim. The artwork has a second at 0.53 which cannot be
        /// told apart from this one at status-item size.
        static let irisRadius: CGFloat = 0.56

        /// The pupil. Larger than the artwork's 0.195, which at this size is a dot
        /// too small to read as filled or hollow.
        static let pupilRadius: CGFloat = 0.27

        /// The hanging loop: a ring, drawn as a stroked circle.
        static let loopCenter: CGFloat = -1.08
        static let loopRadius: CGFloat = 0.16

        /// The three beads on the cord, nearest the charm first.
        static let beads: [(center: CGFloat, radius: CGFloat)] = [
            (-1.45, 0.17),
            (-1.84, 0.235),
            (-2.18, 0.163)
        ]

        /// The highest edge of anything drawn, which is the top of the last bead.
        static var top: CGFloat {
            beads.map { $0.center - $0.radius }.min() ?? -bodyRadius
        }
        static var height: CGFloat { bodyRadius - top }
        static var width: CGFloat { bodyRadius * 2 }
    }

    /// Stroke weight as a fraction of the charm's radius, chosen so the thinnest
    /// line lands near one point at the shipped size.
    private static let strokeWeight: CGFloat = 0.2

    // MARK: - Drawing

    private static func render(showing: Bool) -> NSImage {
        let image = NSImage(size: CGSize(width: side, height: side), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(showing: showing, in: context)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(showing: Bool, in context: CGContext) {
        // Fit the artwork's bounding box into the square, leaving room for the
        // stroke, which straddles every path it is drawn on. The box is not centred
        // on the charm — the cord hangs above it — so the charm's own centre lands
        // below the middle of the square.
        // A little short of the full square, so a tall narrow charm does not tower
        // over the square icons either side of it in the bar.
        let inset: CGFloat = 0.75
        let scale = (side - (inset * 2)) / max(Artwork.height + strokeWeight, Artwork.width + strokeWeight)
        let boxCenterY = (Artwork.top + Artwork.bodyRadius) / 2
        let center = CGPoint(x: side / 2, y: (side / 2) - (boxCenterY * scale))

        context.setStrokeColor(NSColor.black.cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.setLineWidth(strokeWeight * scale)

        func circle(_ centerY: CGFloat, _ radius: CGFloat) -> CGRect {
            CGRect(
                x: center.x - (radius * scale),
                y: center.y + (centerY * scale) - (radius * scale),
                width: radius * scale * 2,
                height: radius * scale * 2
            )
        }

        // The cord's beads and the loop it ends in.
        for bead in Artwork.beads {
            context.fillEllipse(in: circle(bead.center, bead.radius))
        }
        context.strokeEllipse(in: circle(Artwork.loopCenter, Artwork.loopRadius))

        // The charm: rim, iris, and a pupil that is open while the overlay is.
        context.strokeEllipse(in: circle(0, Artwork.bodyRadius))
        context.strokeEllipse(in: circle(0, Artwork.irisRadius))
        if showing {
            context.fillEllipse(in: circle(0, Artwork.pupilRadius))
        } else {
            context.strokeEllipse(in: circle(0, Artwork.pupilRadius))
        }
    }
}
