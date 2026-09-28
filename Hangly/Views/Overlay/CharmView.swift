//
//  CharmView.swift
//  Hangly
//
//  A single charm, drawn on its own.
//

import SwiftUI

/// Renders one charm centred in the space it is given.
///
/// The overlay draws charms straight into the rope's canvas, so this view exists for
/// everything else: previews, and rendering a charm in isolation without a running
/// simulation. It shares `CharmRenderer` with the overlay, so what it shows is
/// exactly what hangs on the rope.
struct CharmView: View {
    let charm: any Charm

    /// Fraction of the available half-extent the charm occupies.
    var inset: Double = 0.84

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let radius = (min(size.width, size.height) / 2) * inset
            CharmRenderer.draw(
                charm: charm,
                into: &context,
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                radius: radius
            )
        }
        .accessibilityLabel(charm.displayName)
    }
}

#if DEBUG
#Preview("Built-in charms") {
    HStack(spacing: 8) {
        ForEach(CharmKind.allCases) { kind in
            CharmView(charm: BuiltInCharms.charm(for: kind))
                .frame(width: 72, height: 72)
        }
    }
    .padding()
    .background(Color(white: 0.12))
}
#endif
