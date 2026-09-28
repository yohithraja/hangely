//
//  SVGAssetTests.swift
//  HanglyTests
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Hangly

/// The collection's artwork now comes from SVG assets. These tests hold the
/// contract: every catalogue entry has an asset, missing ones are reported, and
/// nothing about physics changed in the move.
@Suite("SVG charm assets")
struct SVGAssetTests {
    private let bundled = SVGArtworkSource(backend: .bundle)

    @Test("Every collection charm in the metadata document resolves to a bundled SVG")
    func everyEntryResolvesToAnAsset() {
        let library = CharmLibrary.bundled()
        for entry in library.entries {
            guard let kind = entry.kind, CollectionCharmCatalog.kinds.contains(kind) else { continue }
            #expect(bundled.isAvailable(kind), "no SVG asset for \(entry.id)")
            #expect(Bundle.main.image(forResource: SVGArtworkSource.assetName(for: kind)) != nil)
        }
        #expect(bundled.missingAssets(among: CollectionCharmCatalog.kinds).isEmpty)
        #expect(BuiltInCharms.missingArtwork.isEmpty)
    }

    @Test("The Library shows the whole piece; the rope hangs it in parts")
    func artworkSplitsOnlyForTheRope() throws {
        let daruma = BuiltInCharms.charm(for: .daruma)
        // What the Library, the Studio and the previews draw: one complete charm.
        #expect(daruma.artwork().bodyRegion == nil)
        #expect(daruma.artwork().beadRegions.isEmpty)

        // What hangs: the charm, with its beads handed to the rope.
        let hanging = daruma.hangingArtwork()
        let body = try #require(hanging.bodyRegion)
        #expect(hanging.beadRegions.count == daruma.beads.count)
        for bead in hanging.beadRegions {
            #expect(bead.maxY <= body.minY)
        }

        // A charm with no beads hangs exactly as it is drawn.
        let himmeli = BuiltInCharms.charm(for: .himmeli)
        #expect(himmeli.hangingArtwork().beadRegions.isEmpty)
        #expect(BuiltInCharms.charm(for: .circle).hangingArtwork().vector == nil)
    }

    @Test("Every built-in resolves to exactly one kind of artwork")
    func builtInsHaveArtwork() {
        for charm in BuiltInCharms.all {
            let artwork = charm.artwork()
            if charm is SVGCharm {
                #expect(artwork.vector != nil, "\(charm.displayName) should be vector-backed")
                #expect(artwork.bitmap == nil)
            } else {
                #expect(artwork.vector == nil)
                #expect(!artwork.silhouette.isEmpty, "\(charm.displayName) should have geometry")
            }
        }
        #expect(BuiltInCharms.all.filter { $0 is SVGCharm }.count == CollectionCharmCatalog.entries.count)
    }

    @Test("Missing assets are reported, and a charm without one still draws")
    func missingAssetsAreReported() throws {
        let empty = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: empty) }
        let source = SVGArtworkSource(backend: .directory(empty))

        #expect(source.missingAssets(among: CollectionCharmCatalog.kinds) == CollectionCharmCatalog.kinds)
        #expect(source.vectorImage(for: .nazar) == nil)

        // Copy one real asset in: only the rest are missing.
        let repoAssets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Assets/Charms")
        let nazarFile = try #require(CollectionCharmCatalog.sourceFileName(for: .nazar))
        if FileManager.default.fileExists(atPath: repoAssets.appending(path: nazarFile).path) {
            try FileManager.default.copyItem(
                at: repoAssets.appending(path: nazarFile),
                to: empty.appending(path: nazarFile)
            )
            let partial = SVGArtworkSource(backend: .directory(empty))
            #expect(partial.isAvailable(.nazar))
            let missing = partial.missingAssets(among: CollectionCharmCatalog.kinds)
            #expect(missing.count == CollectionCharmCatalog.kinds.count - 1)
        }

        // A charm whose asset is absent falls back to a placeholder, never nothing.
        // Nazar's file was just copied in, so use the next entry, which was not.
        let charms = CollectionCharmCatalog.charms(source: SVGArtworkSource(backend: .directory(empty)))
        let bare = try #require(charms[1] as? SVGCharm)
        #expect(bare.kind == CollectionCharmCatalog.entries[1].kind)
        #expect(bare.vector == nil)
        #expect(!bare.artwork().silhouette.isEmpty)
        #expect(bare.metrics.mass == CollectionCharmCatalog.entries[1].mass)
    }

    @Test("Every charm's mass and sound are unchanged, and its size is the shipped one")
    func physicsTable() {
        struct Expected {
            let kind: CharmKind
            let mass: Double
            let radius: Double
            let sound: CharmSound
        }
        // Mass and sound are exactly as they shipped. The radii are tuned against
        // the artwork so a charm hangs at the size the design calls for; the ratios
        // between charms are untouched.
        let expected = [
            Expected(kind: .nazar, mass: 2.75, radius: 0.145, sound: .glass),
            Expected(kind: .hamsa, mass: 3.05, radius: 0.158, sound: .metal),
            Expected(kind: .nimbuMirchi, mass: 2.85, radius: 0.152, sound: .soft),
            Expected(kind: .ghanta, mass: 4.05, radius: 0.150, sound: .bell),
            Expected(kind: .drishtiBommai, mass: 3.25, radius: 0.164, sound: .wood),
            Expected(kind: .panchangJie, mass: 2.45, radius: 0.160, sound: .soft),
            Expected(kind: .daruma, mass: 3.65, radius: 0.154, sound: .wood),
            Expected(kind: .manekiNeko, mass: 3.45, radius: 0.167, sound: .wood),
            Expected(kind: .horseshoe, mass: 3.85, radius: 0.151, sound: .metal),
            Expected(kind: .scarab, mass: 3.15, radius: 0.146, sound: .glass),
            Expected(kind: .himmeli, mass: 2.35, radius: 0.169, sound: .soft)
        ]
        #expect(expected.count == CollectionCharmCatalog.entries.count)
        for item in expected {
            let charm = BuiltInCharms.charm(for: item.kind)
            #expect(charm.metrics.mass == item.mass, "\(item.kind) mass")
            #expect(charm.metrics.radiusRatio == item.radius, "\(item.kind) radius")
            #expect(charm.sound == item.sound, "\(item.kind) sound")
            #expect(charm.id == .builtIn(item.kind))
        }
    }

    @Test("Every charm hangs at the size the design calls for")
    func charmsHangAtTheRightSize() {
        let rope = RopeConfiguration.fitted(to: AppConstants.Overlay.baseSize)
        func hangingHeight(_ charm: any Charm) -> Double {
            rope.totalLength * charm.metrics.radiusRatio * 2
        }

        // Judged against the artwork on screen. Their own loops are part of this, so
        // the charm itself reads a little smaller than the number.
        for kind in CollectionCharmCatalog.kinds {
            let height = hangingHeight(BuiltInCharms.charm(for: kind))
            #expect(height >= 80, "\(kind) hangs at only \(height) points")
            #expect(height <= 104, "\(kind) hangs at \(height) points")
        }

        // The classics are bare shapes with no loop above them, so they sit a little
        // under the collection rather than matching its bounds.
        for charm in BuiltInCharms.all where !(charm is SVGCharm) {
            let height = hangingHeight(charm)
            #expect(height >= 68, "\(charm.displayName) hangs at only \(height) points")
            #expect(height <= 104, "\(charm.displayName) hangs at \(height) points")
        }
    }

    @Test("A charm and its cord fit the overlay even at full reach")
    func overlayHoldsTheWholeAssembly() {
        let size = AppConstants.Overlay.baseSize
        let rope = RopeConfiguration.fitted(to: size)
        let anchor = RopeConfiguration.Layout.anchor(in: size)
        let widest = BuiltInCharms.all.map(\.metrics.radiusRatio).max() ?? 0
        let reach = (rope.totalLength * rope.maximumReachRatio) + (rope.totalLength * widest)

        #expect(anchor.y + reach <= size.height)
        #expect(reach <= size.width / 2)
    }

    @Test("A vector asset rasterises at the requested size with transparency, and caches")
    func rasterises() throws {
        let vector = try #require(bundled.vectorImage(for: .nazar))

        let small = try #require(vector.raster(pixelSide: 96, dark: false))
        #expect(small.width == 96)
        #expect(small.height == 96)
        let bitmap = try #require(RGBABitmap(image: small))
        #expect(bitmap.alpha(x: 0, y: 0) == 0)
        #expect(bitmap.coverage(threshold: 8) > 0.08)
        #expect(bitmap.coverage(threshold: 8) < 0.6)

        let again = try #require(vector.raster(pixelSide: 96, dark: false))
        #expect(small === again)

        let large = try #require(vector.raster(pixelSide: 512, dark: false))
        #expect(large.width == 512)
        #expect(large !== small)

        let dark = try #require(vector.raster(pixelSide: 96, dark: true))
        #expect(dark.width == 96)
    }

    @Test("The collection's cord is gold; the classics keep their own colours")
    func cordTint() {
        #expect(BuiltInCharms.charm(for: .nazar).cordTint == CollectionCharmCatalog.cordTint)
        #expect(BuiltInCharms.charm(for: .circle).cordTint == nil)
    }

    @Test("The renderer draws a vector charm with visible pixels")
    @MainActor
    func rendersThroughTheRenderer() throws {
        let charm = BuiltInCharms.charm(for: .daruma)
        let renderer = ImageRenderer(content: CharmView(charm: charm).frame(width: 80, height: 80))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let bitmap = try #require(RGBABitmap(image: image))
        #expect(bitmap.coverage(threshold: 8) > 0.05)
    }
}
