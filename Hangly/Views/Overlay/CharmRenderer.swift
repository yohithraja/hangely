//
//  CharmRenderer.swift
//  Hangly
//
//  Turns a charm's geometry into pixels.
//

import CoreGraphics
import SwiftUI

extension CharmColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// Draws any `Charm` with one shared lighting model.
///
/// Charms describe shapes; this decides how they are lit. Keeping that split means
/// the whole set shares a light direction, a shadow softness and a rim treatment, so
/// a camera and a heart look like they came from the same box. Imported bitmaps get
/// the same shadow and highlight, applied through their own alpha, so they read as
/// members of the set rather than stickers laid on top of it.
///
/// Everything is drawn at the canvas's own scale, so the result is resolution
/// independent and stays crisp on Retina displays at any charm size.
enum CharmRenderer {
    /// Light comes from the upper left, consistently for every charm.
    private static let lightSource = UnitPoint(x: 0.33, y: 0.28)

    /// Convenience for one-off renders such as Library cards, where building the
    /// artwork each time is fine. The overlay uses the `artwork:` form with a
    /// cached artwork instead.
    static func draw(
        charm: any Charm,
        into context: inout GraphicsContext,
        center: CGPoint,
        radius: Double,
        opacity: Double = 1
    ) {
        draw(
            artwork: charm.artwork(),
            palette: charm.palette,
            into: &context,
            center: center,
            radius: radius,
            opacity: opacity
        )
    }

    /// A soft halo in the charm's own colour, drawn behind it. Kept faint: it should
    /// read as the charm catching light, not as a glow effect. A radial gradient
    /// rather than a blur filter, so it costs no offscreen layer per frame.
    static func drawAmbientGlow(
        palette: CharmPalette,
        into context: inout GraphicsContext,
        center: CGPoint,
        radius: Double,
        opacity: Double = 1
    ) {
        guard radius > 2, opacity > 0.001 else { return }
        let haloRadius = radius * 1.7
        let tint = palette.primary
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - haloRadius,
                y: center.y - haloRadius,
                width: haloRadius * 2,
                height: haloRadius * 2
            )),
            with: .radialGradient(
                Gradient(colors: [
                    tint.withAlpha(0.20 * opacity).swiftUIColor,
                    tint.withAlpha(0.08 * opacity).swiftUIColor,
                    tint.withAlpha(0).swiftUIColor
                ]),
                center: center,
                startRadius: radius * 0.8,
                endRadius: haloRadius
            )
        )
    }

    /// - Parameters:
    ///   - rotation: Radians to turn vector artwork about its centre, so an asset
    ///     that hangs from a cord stays in line with the rope. Ignored for geometry
    ///     and bitmaps.
    ///   - bodyOnly: Draw just the charm, leaving out the beads its artwork also
    ///     contains. The overlay hangs those on the cord itself; everywhere else
    ///     shows the complete piece.
    static func draw(
        artwork: CharmArtwork,
        palette: CharmPalette,
        into context: inout GraphicsContext,
        center: CGPoint,
        radius: Double,
        opacity: Double = 1,
        rotation: Double = 0,
        bodyOnly: Bool = false
    ) {
        guard radius > 0.5, opacity > 0.001 else { return }

        let side = radius * 2
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: side, height: side)

        if let vector = artwork.vector {
            drawVector(
                vector,
                region: bodyOnly ? artwork.bodyRegion : nil,
                placement: VectorPlacement(
                    center: center,
                    radius: radius,
                    opacity: opacity,
                    rotation: rotation
                ),
                into: &context
            )
            return
        }

        if let bitmap = artwork.bitmap {
            drawBitmap(bitmap, into: &context, rect: rect, opacity: opacity, highlight: true)
            return
        }

        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: side, y: side)
        let silhouette = Path(artwork.silhouette).applying(transform)

        context.drawLayer { layer in
            layer.opacity = opacity
            drawShadow(silhouette, into: &layer, palette: palette, radius: radius)
            drawBody(silhouette, into: &layer, palette: palette, rect: rect)
            drawDetails(artwork.details, into: &layer, palette: palette, transform: transform, side: side)
            drawHighlight(into: &layer, rect: rect) { $0.clip(to: silhouette) }
            drawRim(silhouette, into: &layer, radius: radius)
        }
    }

    // MARK: - Bitmap charms

    static func drawBitmap(
        _ bitmap: CGImage,
        into context: inout GraphicsContext,
        rect: CGRect,
        opacity: Double,
        highlight: Bool,
        shadowed: Bool = true
    ) {
        let radius = min(rect.width, rect.height) / 2
        let image = Image(decorative: bitmap, scale: 1).interpolation(.high)

        context.drawLayer { layer in
            layer.opacity = opacity

            // The shadow follows the image's alpha exactly, so a cut-out subject
            // casts the shape of itself and not of its bounding box.
            if shadowed {
                layer.drawLayer { shadow in
                    shadow.addFilter(.shadow(
                        color: .black.opacity(0.34),
                        radius: radius * 0.30,
                        x: 0,
                        y: radius * 0.16
                    ))
                    shadow.draw(image, in: rect)
                }
            }

            layer.draw(image, in: rect)

            guard highlight else { return }
            drawHighlight(into: &layer, rect: rect) { bloomLayer in
                bloomLayer.clipToLayer { mask in
                    mask.draw(image, in: rect)
                }
            }
        }
    }

    // MARK: - Layers

    /// Soft contact shadow, offset downward so charms feel lit from above.
    private static func drawShadow(
        _ silhouette: Path,
        into context: inout GraphicsContext,
        palette: CharmPalette,
        radius: Double
    ) {
        context.drawLayer { layer in
            layer.addFilter(.shadow(
                color: .black.opacity(0.34),
                radius: radius * 0.30,
                x: 0,
                y: radius * 0.16
            ))
            layer.fill(silhouette, with: .color(palette.secondary.swiftUIColor))
        }
    }

    /// Body shading: bright near the light source, falling to the darkest tone.
    private static func drawBody(
        _ silhouette: Path,
        into context: inout GraphicsContext,
        palette: CharmPalette,
        rect: CGRect
    ) {
        context.fill(silhouette, with: .radialGradient(
            Gradient(colors: [
                palette.light.swiftUIColor,
                palette.primary.swiftUIColor,
                palette.secondary.swiftUIColor
            ]),
            center: CGPoint(
                x: rect.minX + (rect.width * lightSource.x),
                y: rect.minY + (rect.height * lightSource.y)
            ),
            startRadius: 0,
            endRadius: rect.width * 0.95
        ))
    }

    private static func drawDetails(
        _ details: [CharmDetail],
        into context: inout GraphicsContext,
        palette: CharmPalette,
        transform: CGAffineTransform,
        side: Double
    ) {
        for detail in details {
            let path = Path(detail.path).applying(transform)
            switch detail.style {
            case .fill(let ink):
                context.fill(path, with: .color(palette.color(for: ink).swiftUIColor))
            case .stroke(let ink, let width):
                context.stroke(
                    path,
                    with: .color(palette.color(for: ink).swiftUIColor.opacity(0.65)),
                    lineWidth: max(0.5, width * side)
                )
            }
        }
    }

    /// A specular bloom, which is what stops flat shapes reading as stickers.
    /// - Parameter clip: Restricts the bloom to the charm; a path for vectors, the
    ///   image's own alpha for bitmaps.
    private static func drawHighlight(
        into context: inout GraphicsContext,
        rect: CGRect,
        clip: (inout GraphicsContext) -> Void
    ) {
        context.drawLayer { layer in
            clip(&layer)

            let bloom = CGRect(
                x: rect.minX + (rect.width * 0.08),
                y: rect.minY + (rect.height * 0.04),
                width: rect.width * 0.56,
                height: rect.height * 0.38
            )
            layer.fill(Path(ellipseIn: bloom), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.50), .white.opacity(0)]),
                center: CGPoint(x: bloom.midX, y: bloom.midY),
                startRadius: 0,
                endRadius: bloom.width * 0.62
            ))
        }
    }

    private static func drawRim(
        _ silhouette: Path,
        into context: inout GraphicsContext,
        radius: Double
    ) {
        context.stroke(
            silhouette,
            with: .color(.white.opacity(0.30)),
            lineWidth: max(0.75, radius * 0.07)
        )
    }
}
