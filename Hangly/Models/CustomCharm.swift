//
//  CustomCharm.swift
//  Hangly
//
//  An imported image as a charm.
//

import CoreGraphics
import Foundation

/// What is persisted about an imported charm, without the pixels.
///
/// Kept separate from the charm itself so the menu can list every import without
/// loading a single bitmap. Metrics and palette are computed once at import time
/// from the processed image and stored, so a launch never has to analyse pixels.
struct CustomCharmEntry: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var createdAt: Date

    /// File name of the processed PNG inside the charm store's directory.
    var imageFileName: String

    var metrics: CharmMetrics
    var palette: CharmPalette
}

/// An imported image hanging on the rope.
///
/// Physically it is a charm like any other: it has a mass, which is derived from
/// how much of its square the image actually fills, and a size. Visually it is a
/// bitmap that `CharmRenderer` lights through its own alpha, so it gets the same
/// shadow and highlight as the built-ins.
struct CustomCharm: Charm {
    let entry: CustomCharmEntry
    let bitmap: CGImage

    var id: CharmID { .custom(entry.id) }
    var displayName: String { entry.name }
    var symbolName: String { "photo.fill" }
    var metrics: CharmMetrics { entry.metrics }
    var palette: CharmPalette { entry.palette }

    func artwork() -> CharmArtwork {
        CharmArtwork(bitmap: bitmap)
    }
}
