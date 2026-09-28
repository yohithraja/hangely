//
//  BuiltInCharms.swift
//  Hangly
//
//  The shipped charm set.
//

/// Every built-in charm, in menu order: the Hangly collection, then the classics.
///
/// The collection leads because it is what the app is for; the classics are plain
/// shapes and sit underneath it. The collection is drawn from SVG assets resolved
/// through `SVGArtworkSource`, the classics from vector geometry in code. A
/// free-standing lookup rather than a method on a service, so previews, scripts and
/// tests can resolve a charm without building the whole object graph.
enum BuiltInCharms {
    static let all: [any Charm] = CollectionCharmCatalog.charms(
        source: SVGArtworkSource.resolveDefault()
    ) + [
        CircleCharm(),
        CameraCharm(),
        StarCharm(),
        HeartCharm(),
        DiamondCharm()
    ]

    /// Falls back to the circle, so an unknown kind can never leave the rope bare.
    static func charm(for kind: CharmKind) -> any Charm {
        all.first { $0.id == .builtIn(kind) } ?? CircleCharm()
    }

    /// Collection charms whose SVG asset could not be found.
    static var missingArtwork: [CharmKind] {
        all.compactMap { charm in
            guard let svg = charm as? SVGCharm, svg.vector == nil else { return nil }
            return svg.kind
        }
    }
}
