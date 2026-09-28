//
//  RopeCanvasView+Debug.swift
//  Hangly
//
//  The developer overlay: every node, every bead, and the numbers behind them.
//

import SwiftUI

// Development only: the whole overlay is compiled out of production builds.
#if !HANGLY_PRODUCTION

/// Drawn only when `AppConstants.Debug.ropeOverlayKey` is set. Kept apart from the
/// renderer proper so the shipping drawing path stays easy to read.
extension RopeCanvasView {
    func drawDebugSkeleton(in context: inout GraphicsContext) {
        var skeleton = Path()
        skeleton.addLines(snapshot.points)
        context.stroke(skeleton, with: .color(.green.opacity(0.6)), lineWidth: 1)

        for bead in snapshot.beads {
            let radius = max(2, bead.size.height / 2)
            let rect = CGRect(
                x: bead.position.x - radius,
                y: bead.position.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(Path(ellipseIn: rect), with: .color(.yellow.opacity(0.85)), lineWidth: 1)
        }

        for (index, point) in snapshot.points.enumerated() {
            let style = debugStyle(for: index)
            let rect = CGRect(
                x: point.x - style.radius,
                y: point.y - style.radius,
                width: style.radius * 2,
                height: style.radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(style.color))
            context.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.6)), lineWidth: 0.5)
        }
    }

    func debugStyle(for index: Int) -> (color: Color, radius: Double) {
        if index == 0 {
            return (.orange, 5)
        }
        if index == snapshot.points.count - 1 {
            return (.red, 5)
        }
        return (.cyan, 3)
    }

    func drawDebugReadout(in context: inout GraphicsContext, size: CGSize) {
        guard !debugSummary.isEmpty else { return }

        let resolved = context.resolve(
            Text(debugSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
        )
        let textSize = resolved.measure(in: size)
        let padding = 7.0
        let box = CGRect(
            x: 10,
            y: 10,
            width: textSize.width + (padding * 2),
            height: textSize.height + (padding * 2)
        )

        context.fill(
            Path(roundedRect: box, cornerRadius: 6),
            with: .color(.black.opacity(0.62))
        )
        context.draw(
            resolved,
            at: CGPoint(x: box.minX + padding, y: box.minY + padding),
            anchor: .topLeading
        )
    }
}

#endif
