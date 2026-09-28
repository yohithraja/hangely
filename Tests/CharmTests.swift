//
//  CharmTests.swift
//  HanglyTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Hangly

/// Charms are pure geometry and numbers, so the whole set can be checked without
/// rendering anything.
@Suite("Charms")
struct CharmTests {
    @Test("Every kind resolves to a charm that agrees about its own identity")
    func registryCoversEveryKind() {
        for kind in CharmKind.allCases {
            #expect(BuiltInCharms.charm(for: kind).id == .builtIn(kind))
        }
        #expect(BuiltInCharms.all.count == CharmKind.allCases.count)
    }

    @Test("The classic charms are still present")
    func shipsTheClassics() {
        let classics: Set<CharmKind> = [.circle, .camera, .star, .heart, .diamond]
        #expect(classics.isSubset(of: Set(CharmKind.allCases)))
        #expect(CharmKind.allCases.count == 16)
    }

    @Test("Every charm has sane physical properties")
    func metricsAreSane() {
        for charm in BuiltInCharms.all {
            let metrics = charm.metrics
            #expect(metrics.mass > 0)
            #expect(metrics.radiusRatio > 0.01)
            #expect(metrics.radiusRatio < 0.5)
            #expect(metrics.knotInset >= 0)
            #expect(metrics.knotInset <= 1)
        }
    }

    @Test("Charms differ in both mass and size")
    func charmsAreDistinct() {
        let masses = Set(BuiltInCharms.all.map(\.metrics.mass))
        let radii = Set(BuiltInCharms.all.map(\.metrics.radiusRatio))

        #expect(masses.count == BuiltInCharms.all.count)
        #expect(radii.count == BuiltInCharms.all.count)
    }

    @Test("Geometry artwork is non-empty and stays inside its unit square")
    func artworkIsWellFormed() {
        for charm in BuiltInCharms.all {
            let artwork = charm.artwork()
            guard artwork.vector == nil else { continue }   // SVG assets are checked in SVGAssetTests
            let bounds = artwork.silhouette.boundingBox

            #expect(artwork.bitmap == nil)
            #expect(!artwork.silhouette.isEmpty)
            #expect(bounds.width > 0.2)
            #expect(bounds.height > 0.2)
            // A small tolerance for curve control points bulging past the edge.
            #expect(bounds.minX >= -0.03)
            #expect(bounds.minY >= -0.03)
            #expect(bounds.maxX <= 1.03)
            #expect(bounds.maxY <= 1.03)

            for detail in artwork.details {
                #expect(!detail.path.isEmpty)
            }
        }
    }

    @Test("Metric interpolation hits both ends and the middle")
    func metricsInterpolate() {
        let start = CharmMetrics(mass: 2, radiusRatio: 0.1, knotInset: 0.8)
        let end = CharmMetrics(mass: 4, radiusRatio: 0.2, knotInset: 1.0)

        #expect(CharmMetrics.interpolate(from: start, to: end, progress: 0) == start)
        #expect(CharmMetrics.interpolate(from: start, to: end, progress: 1) == end)

        let middle = CharmMetrics.interpolate(from: start, to: end, progress: 0.5)
        #expect(abs(middle.mass - 3) < 1e-9)
        #expect(abs(middle.radiusRatio - 0.15) < 1e-9)

        // Out-of-range progress is clamped, not extrapolated.
        #expect(CharmMetrics.interpolate(from: start, to: end, progress: 3) == end)
        #expect(CharmMetrics.interpolate(from: start, to: end, progress: -3) == start)
    }

    @Test("Palette interpolation blends every tone")
    func palettesInterpolate() {
        let circle = CircleCharm().palette
        let heart = HeartCharm().palette

        #expect(CharmPalette.interpolate(from: circle, to: heart, progress: 0) == circle)
        #expect(CharmPalette.interpolate(from: circle, to: heart, progress: 1) == heart)

        let middle = CharmPalette.interpolate(from: circle, to: heart, progress: 0.5)
        #expect(abs(middle.primary.red - ((circle.primary.red + heart.primary.red) / 2)) < 1e-9)
    }

    @Test("A derived palette keeps the base as primary and darkens the rest")
    func derivedPaletteIsOrdered() {
        let base = CharmColor(0.8, 0.5, 0.3)
        let palette = CharmPalette.derived(from: base)

        #expect(palette.primary == base)
        #expect(palette.secondary.red < base.red)
        #expect(palette.deep.red < palette.secondary.red)
        #expect(palette.light.red > base.red)
    }
}

/// `CharmID` is what ends up in the settings document, so its string form is a
/// compatibility contract: a built-in must still be written exactly as before
/// Phase 4, and an import must round-trip.
@Suite("Charm identity")
struct CharmIDTests {
    @Test("A built-in is stored as its plain kind name, unchanged from before")
    func builtInStoresAsKindName() throws {
        let id = CharmID.builtIn(.star)
        #expect(id.storageValue == "star")

        let encoded = try JSONEncoder().encode([id])
        #expect(String(bytes: encoded, encoding: .utf8) == #"["star"]"#)
    }

    @Test("An import round-trips through its storage string")
    func customRoundTrips() throws {
        let uuid = UUID()
        let id = CharmID.custom(uuid)

        #expect(id.isCustom)
        #expect(CharmID(storageValue: id.storageValue) == id)

        let encoded = try JSONEncoder().encode([id])
        let decoded = try JSONDecoder().decode([CharmID].self, from: encoded)
        #expect(decoded == [id])
    }

    @Test("A settings document from before Phase 4 still decodes")
    func legacyKindStringDecodes() throws {
        let decoded = try JSONDecoder().decode([CharmID].self, from: Data(#"["heart"]"#.utf8))
        #expect(decoded == [.builtIn(.heart)])
    }

    @Test("Garbage is refused rather than guessed")
    func unknownStringIsRejected() {
        #expect(CharmID(storageValue: "sparkle") == nil)
        #expect(CharmID(storageValue: "custom:not-a-uuid") == nil)
        #expect(CharmID(storageValue: "") == nil)
    }
}

/// The selection lives in the settings document, so it has to survive a round trip
/// and tolerate a document written by a build that knows different charms.
@Suite("Charm selection")
@MainActor
struct CharmSelectionTests {
    /// A manager over throwaway settings and a throwaway charm directory.
    private struct Fixture {
        let manager: CharmManager
        let defaults: UserDefaults
        let suiteName: String
        let directory: URL

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "com.hangly.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = try TestImages.temporaryDirectory()
        let store = SettingsStore(defaults: defaults, storageKey: "settings")
        let manager = CharmManager(settingsStore: store, customStore: CustomCharmStore(directory: directory))
        return Fixture(manager: manager, defaults: defaults, suiteName: suiteName, directory: directory)
    }

    @Test("A fresh install starts on the shipped default charm")
    func defaultsToTheShippedCharm() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        #expect(fixture.manager.selection == OverlaySettings().charm)
        #expect(fixture.manager.canDeleteCurrent == false)
    }

    @Test("Choosing a charm persists across a reload")
    func selectionPersists() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.manager.selection = .builtIn(.star)

        let reloaded = SettingsStore(defaults: fixture.defaults, storageKey: "settings")
        let manager = CharmManager(settingsStore: reloaded, customStore: CustomCharmStore(directory: fixture.directory))
        #expect(manager.selection == .builtIn(.star))
    }

    @Test("The menu lists every built-in first, in registry order")
    func menuStartsWithBuiltIns() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        #expect(fixture.manager.menuItems.map(\.id) == BuiltInCharms.all.map(\.id))
    }

    @Test("A charm name this build does not know falls back without losing other settings")
    func unknownCharmDegradesGracefully() throws {
        let json = #"{"opacity": 0.42, "charm": "sparkle", "anchor": "bottomCentre"}"#
        let decoded = try JSONDecoder().decode(OverlaySettings.self, from: Data(json.utf8))

        #expect(decoded.charm == OverlaySettings().charm)
        #expect(decoded.anchor == OverlaySettings().anchor)
        #expect(decoded.opacity == 0.42)
    }

    @Test("Known built-in and custom identifiers decode")
    func knownIdentifiersDecode() throws {
        let uuid = UUID()
        let json = #"{"charm": "custom:\#(uuid.uuidString)"}"#
        let decoded = try JSONDecoder().decode(OverlaySettings.self, from: Data(json.utf8))
        #expect(decoded.charm == .custom(uuid))

        let builtIn = try JSONDecoder().decode(OverlaySettings.self, from: Data(#"{"charm": "diamond"}"#.utf8))
        #expect(builtIn.charm == .builtIn(.diamond))
    }

    @Test("A selected import that no longer exists falls back to the circle")
    func missingImportFallsBack() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.manager.selection = .custom(UUID())

        // The repair charm, which is deliberately the plainest one rather than
        // whatever the shipped default happens to be.
        #expect(fixture.manager.current.id == .builtIn(.circle))
    }

    @Test("At launch, a selection or favourite pointing at a missing import is repaired")
    func reconcilesGhostsAtLaunch() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let ghost = UUID()
        let store = SettingsStore(defaults: fixture.defaults, storageKey: "settings")
        store.update {
            $0.overlay.charm = .custom(ghost)
            $0.favoriteCharms = [.custom(ghost), .builtIn(.star)]
        }

        let manager = CharmManager(settingsStore: store, customStore: CustomCharmStore(directory: fixture.directory))

        #expect(manager.selection == .builtIn(.circle))
        #expect(store.settings.overlay.charm == .builtIn(.circle))
        #expect(store.settings.favoriteCharms == [.builtIn(.star)])
    }
}
