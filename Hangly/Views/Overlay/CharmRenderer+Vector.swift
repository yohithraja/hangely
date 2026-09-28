//
//  CharmRenderer+Vector.swift
//  Hangly
//
//  Drawing SVG-backed charms and the beads that hang above them.
//

import CoreGraphics
import SwiftUI

/// The vector path through the renderer.
///
/// An SVG asset is one picture containing a charm and the beads threaded above it.
/// The overlay needs those as separate sprites in separate places, so every draw
/// here takes the region of the asset it wants and rasterises just that, at the size
/// it will appear. Because the source is vector, a region blown up to fill its
/// target is as sharp as the whole asset would be.
extension CharmRenderer {
    /// Draws one bead of a charm's artwork at the place the simulation put it.
    ///
    /// The bead's own slice of the asset is rasterised at the size it is drawn, so
    /// a bead is as sharp as the charm it came from rather than a crop of a larger
    /// bitmap.
    static func drawBead(
        artwork: CharmArtwork,
        index: Int,
        placement: BeadPlacement,
        into context: inout GraphicsContext,
        opacity: Double = 1
    ) {
        guard opacity > 0.001,
              let vector = artwork.vector,
              artwork.beadRegions.indices.contains(index) else { return }

        let region = artwork.beadRegions[index]
        let longest = max(region.width, region.height)
        guard longest > 0 else { return }

        // Sized from this artwork's own proportions, so a charm fading out during a
        // change keeps its beads' shapes instead of borrowing the new charm's.
        let scale = max(placement.size.width, placement.size.height) / longest
        let radius = max(region.width, region.height) * scale / 2
        guard radius > 0.5 else { return }

        drawVector(
            vector,
            region: region,
            placement: VectorPlacement(
                center: placement.position,
                radius: radius,
                opacity: opacity,
                rotation: placement.angle - (.pi / 2),
                shadowed: false
            ),
            into: &context
        )
    }

    /// Rasterises a vector asset, or one region of it, and draws it.
    ///
    /// The bitmap is produced at the display's real pixel density and the current
    /// appearance, so it is crisp on Retina and honours a dark variant if the asset
    /// has one.
    /// Where and how a piece of vector artwork is to be drawn.
    struct VectorPlacement {
        var center: CGPoint
        var radius: Double
        var opacity: Double = 1
        var rotation: Double = 0

        /// Whether to cast a contact shadow. A charm does; a bead does not, because
        /// several offscreen shadow layers a frame is the cost this renderer exists
        /// to avoid.
        var shadowed: Bool = true
    }

    static func drawVector(
        _ vector: VectorImage,
        region: CGRect?,
        placement: VectorPlacement,
        into context: inout GraphicsContext
    ) {
        let center = placement.center
        let radius = placement.radius
        let scale = context.environment.displayScale
        let dark = context.environment.colorScheme == .dark
        let side = radius * 2

        let target: CGRect
        if let region {
            // A region keeps its own proportions: its longest side spans the charm.
            let longest = max(region.width, region.height)
            guard longest > 0 else { return }
            let width = side * (region.width / longest)
            let height = side * (region.height / longest)
            target = CGRect(
                x: center.x - (width / 2),
                y: center.y - (height / 2),
                width: width,
                height: height
            )
        } else {
            let inset = side * (1 - CharmArtwork.vectorFill) / 2
            target = CGRect(x: center.x - radius, y: center.y - radius, width: side, height: side)
                .insetBy(dx: inset, dy: inset)
        }

        let pixelWidth = rasterPixels(target.width * scale)
        let pixelHeight = rasterPixels(target.height * scale)
        guard let bitmap = vector.raster(
            region: region,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            dark: dark
        ) else { return }

        // Made once per size rather than filtered per frame; see `shadowRaster`.
        let shadow = placement.shadowed
            ? vector.shadowRaster(
                region: region,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                dark: dark,
                opacity: shadowOpacity
            )
            : nil

        context.drawLayer { layer in
            if placement.rotation != 0 {
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .radians(placement.rotation))
                layer.translateBy(x: -center.x, y: -center.y)
            }
            layer.opacity = placement.opacity

            if let shadow {
                let spread = VectorImage.shadowSpread(forPixelSide: min(pixelWidth, pixelHeight))
                let margin = min(target.width, target.height) * spread
                let dropped = target
                    .insetBy(dx: -margin, dy: -margin)
                    .offsetBy(dx: 0, dy: min(target.width, target.height) * shadowDrop)
                layer.draw(Image(decorative: shadow, scale: 1).interpolation(.high), in: dropped)
            }

            // Professional artwork carries its own shading; only the shadow is added.
            layer.draw(Image(decorative: bitmap, scale: 1).interpolation(.high), in: target)
        }
    }

    /// Darkness of a charm's contact shadow at its most solid.
    static var shadowOpacity: Double { 0.34 }

    /// How far the shadow is offset below the charm, as a fraction of its size, so
    /// the whole set reads as lit from above.
    static var shadowDrop: Double { 0.06 }

    /// Rasterisation size, rounded up to a fixed step.
    ///
    /// A charm grows through its settle-in and while the overlay is resized. Asking
    /// for the exact pixel size each frame would rasterise the asset afresh on every
    /// one of those frames; rounding to a step means one bitmap serves the whole
    /// movement, drawn a few percent smaller than it was made, which nothing can see.
    static func rasterPixels(_ pixels: Double) -> Int {
        let step = 32
        let value = max(step, Int(pixels.rounded(.up)))
        return ((value + step - 1) / step) * step
    }
}
