//
//  RopeCanvasView.swift
//  Hangly
//
//  Immediate-mode renderer for the simulated rope and its charm.
//

import SwiftUI

/// Draws the rope, the charm and the optional debug overlay.
///
/// `Canvas` rather than a tree of shape views: at 120 frames per second, rebuilding
/// and diffing twenty-one view identities every frame would dominate the frame
/// budget, whereas a canvas issues drawing commands directly and allocates nothing
/// per node. Everything is vector, drawn at the canvas's own scale, so it stays sharp
/// on Retina displays at any charm size.
///
/// The view is a pure function of its inputs. It never touches the solver, so it
/// renders identically from a hand-written snapshot in a preview or a test.
struct RopeCanvasView: View {
    let snapshot: RopeSnapshot
    let charmLayers: [CharmLayer]
    #if !HANGLY_PRODUCTION
    /// Development only. Set by `OverlayRootView`; absent from production builds.
    var isDebugEnabled = false
    var debugSummary = ""
    #endif

    /// A file is being held over the charm.
    var isDropTargeted = false

    /// Angle of the progress arc while an import runs; `nil` when idle.
    var importSpinnerAngle: Double?

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard snapshot.points.count >= 2 else { return }

            drawRope(in: &context)
            drawBeads(in: &context)
            drawGlow(in: &context)
            drawCharms(in: &context)
            drawKnot(in: &context)
            drawActivity(in: &context)

            #if !HANGLY_PRODUCTION
            if isDebugEnabled {
                drawDebugSkeleton(in: &context)
                drawDebugReadout(in: &context, size: size)
            }
            #endif
        }
    }

    /// The cord takes the charm's colours — or the charm's own cord tint, for artwork
    /// that draws a cord of its own — blended across a change so the whole assembly
    /// reads as one object rather than a charm sitting on a foreign string.
    private var cordPalette: CharmPalette {
        guard let active = charmLayers.last else { return CircleCharm().palette }
        let activeTint = active.charm.cordTint ?? active.charm.palette
        guard charmLayers.count > 1, let outgoing = charmLayers.first else {
            return activeTint
        }
        let outgoingTint = outgoing.charm.cordTint ?? outgoing.charm.palette
        return .interpolate(from: outgoingTint, to: activeTint, progress: active.opacity)
    }

    /// Where the drawn cord ends: at the knot, where the charm's own artwork takes
    /// over. Drawing on to the centre would run a second cord under artwork that
    /// already has one.
    private var cordEnd: CGPoint {
        cordCurve.point(atArc: drawnCordLength)
    }

    // MARK: - Rope

    /// The cord, cut where the charm's artwork takes over.
    ///
    /// Quadratic smoothing through the node midpoints turns a twenty-segment chain
    /// into a continuous curve without needing more nodes in the simulation. The
    /// same `RopeCurve` the solver threads its beads on produces it, so a bead sits
    /// exactly on the line that is drawn rather than near it.
    private var ropePath: Path {
        let points = snapshot.points
        guard points.count > 1 else { return Path() }
        guard !charmLayers.isEmpty else {
            var path = Path()
            path.addLines(cordCurve.polyline(upTo: cordCurve.length))
            return path
        }

        var path = Path()
        path.addLines(cordCurve.polyline(upTo: drawnCordLength))
        return path
    }

    private var cordCurve: RopeCurve {
        RopeCurve(points: snapshot.points, end: snapshot.charmCenter)
    }

    /// Length of cord left once the charm covers its end. Measured exactly as the
    /// solver measures it, from the same curve, so the cord it draws is the cord the
    /// beads were threaded onto.
    private var drawnCordLength: Double {
        cordCurve.arc(
            enteringCircleAround: snapshot.charmCenter,
            radius: snapshot.charmRadius * snapshot.charmKnotInset
        )
    }

    /// A stack of strokes makes a flat line read as a twisted cord: two soft, offset,
    /// low-alpha passes for the shadow, the cord itself, a pair of dashed passes for
    /// the twist, and a thin highlight along its upper-left edge where the light is.
    /// Deliberately no filters: a blur or shadow filter rasterises an offscreen layer
    /// every frame, and at 120 Hz that alone costs tens of megabytes and a good share
    /// of a core. Plain strokes cost nothing beyond the geometry, and the canvas
    /// anti-aliases every one of them.
    private func drawRope(in context: inout GraphicsContext) {
        // A real cord is thin next to what hangs on it. Measured against the charm so
        // it survives a rescale, but deliberately not a constant fraction of it: the
        // cord was tuned at a thickness that reads right and stayed there when the
        // charms grew.
        let width = max(1.5, snapshot.charmRadius * 0.046)
        let palette = cordPalette
        let path = ropePath
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)

        let shadowOffset = CGAffineTransform(translationX: 0, y: width * 0.8)
        let shadowPath = path.applying(shadowOffset)
        context.stroke(
            shadowPath,
            with: .color(.black.opacity(0.10)),
            style: StrokeStyle(lineWidth: width * 2.6, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            shadowPath,
            with: .color(.black.opacity(0.14)),
            style: StrokeStyle(lineWidth: width * 1.5, lineCap: .round, lineJoin: .round)
        )

        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    palette.secondary.withAlpha(0.55).swiftUIColor,
                    palette.primary.swiftUIColor
                ]),
                startPoint: snapshot.anchor,
                endPoint: snapshot.charmCenter
            ),
            style: style
        )

        drawCordTwist(path, in: &context, width: width, palette: palette)

        let highlightPath = path.applying(CGAffineTransform(translationX: -width * 0.18, y: -width * 0.18))
        context.stroke(
            highlightPath,
            with: .color(palette.light.withAlpha(0.38).swiftUIColor),
            style: StrokeStyle(lineWidth: max(0.75, width * 0.3), lineCap: .round, lineJoin: .round)
        )
    }

    /// The twist: short bands running along the cord, lit on one side and shaded on
    /// the other, offset across it so they read as a spiral rather than as rungs.
    ///
    /// Two dashed strokes of the path the cord already has. Dashes are measured along
    /// the path, so the bands follow every bend and stay evenly spaced as the rope
    /// swings, for the cost of two more strokes and no offscreen work at all.
    private func drawCordTwist(
        _ path: Path,
        in context: inout GraphicsContext,
        width: Double,
        palette: CharmPalette
    ) {
        guard width > 1.4 else { return }
        let pitch = width * 1.5
        let across = width * 0.20

        context.stroke(
            path.applying(CGAffineTransform(translationX: -across, y: -across)),
            with: .color(palette.light.withAlpha(0.30).swiftUIColor),
            style: StrokeStyle(
                lineWidth: width * 0.55,
                lineCap: .butt,
                dash: [pitch * 0.42, pitch * 0.58]
            )
        )
        context.stroke(
            path.applying(CGAffineTransform(translationX: across, y: across)),
            with: .color(palette.deep.withAlpha(0.45).swiftUIColor),
            style: StrokeStyle(
                lineWidth: width * 0.45,
                lineCap: .butt,
                dash: [pitch * 0.34, pitch * 0.66],
                dashPhase: pitch * 0.5
            )
        )
    }

    /// The beads threaded on the cord, each turned to lie along it.
    ///
    /// Every layer draws its own beads, so a charm change cross-fades the beads with
    /// the charm they belong to instead of swapping them abruptly.
    private func drawBeads(in context: inout GraphicsContext) {
        guard !snapshot.beads.isEmpty else { return }
        for layer in charmLayers {
            for (index, placement) in snapshot.beads.enumerated() {
                CharmRenderer.drawBead(
                    artwork: layer.artwork,
                    index: index,
                    placement: placement,
                    into: &context,
                    opacity: layer.opacity
                )
            }
        }
    }

    private func drawGlow(in context: inout GraphicsContext) {
        guard let active = charmLayers.last else { return }
        CharmRenderer.drawAmbientGlow(
            palette: active.charm.palette,
            into: &context,
            center: snapshot.charmCenter,
            radius: snapshot.charmRadius * active.scale,
            opacity: active.opacity
        )
    }

    // MARK: - Charm

    private func drawCharms(in context: inout GraphicsContext) {
        // Vector artwork hangs from the cord, so it turns with the final link;
        // geometry and bitmaps keep their screen-fixed lighting.
        let rotation = snapshot.charmAngle - (.pi / 2)
        for layer in charmLayers {
            CharmRenderer.draw(
                artwork: layer.artwork,
                palette: layer.charm.palette,
                into: &context,
                center: snapshot.charmCenter,
                radius: snapshot.charmRadius * layer.scale,
                opacity: layer.opacity,
                rotation: layer.artwork.vector != nil ? rotation : 0,
                // The beads in the artwork hang on the cord instead.
                bodyOnly: true
            )
        }
    }

    /// The loop where the cord meets the charm, oriented along the final link. Each
    /// charm says how far up its own radius that sits, because a heart meets its cord
    /// higher than a bead does.
    private func drawKnot(in context: inout GraphicsContext) {
        let radius = snapshot.charmRadius
        guard radius > 1 else { return }
        // Vector artwork draws its own loop where the cord meets it.
        guard charmLayers.last?.artwork.vector == nil else { return }

        let direction = CGPoint(x: cos(snapshot.charmAngle), y: sin(snapshot.charmAngle))
        let centre = snapshot.charmCenter - (direction * (radius * snapshot.charmKnotInset))
        let ringRadius = radius * 0.2

        let ring = Path(ellipseIn: CGRect(
            x: centre.x - ringRadius,
            y: centre.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))

        context.stroke(
            ring,
            with: .color(cordPalette.light.withAlpha(0.9).swiftUIColor),
            lineWidth: max(1, radius * 0.07)
        )
    }

    // MARK: - Import feedback

    /// A ring around the charm: dashed and steady while a file hovers, a turning
    /// arc while the import runs. Both sit outside the charm so the artwork itself
    /// stays readable.
    private func drawActivity(in context: inout GraphicsContext) {
        let radius = snapshot.charmRadius * 1.45
        guard radius > 2 else { return }
        let centre = snapshot.charmCenter

        if let angle = importSpinnerAngle {
            var arc = Path()
            arc.addArc(
                center: centre,
                radius: radius,
                startAngle: .radians(angle),
                endAngle: .radians(angle + (.pi * 1.4)),
                clockwise: false
            )
            context.stroke(
                arc,
                with: .color(.white.opacity(0.9)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
        } else if isDropTargeted {
            let ring = Path(ellipseIn: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(ring, with: .color(.white.opacity(0.12)))
            context.stroke(
                ring,
                with: .color(.white.opacity(0.85)),
                style: StrokeStyle(lineWidth: 2, dash: [6, 5])
            )
        }
    }
}
