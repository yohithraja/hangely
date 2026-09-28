//
//  CustomCharmStoreTests.swift
//  HanglyTests
//

import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Hangly

/// The store against a throwaway directory. Every test leaves the disk as it
/// found it.
@Suite("Custom charm store")
@MainActor
struct CustomCharmStoreTests {
    private func makeProcessed() throws -> ProcessedCharmImage {
        let image = try #require(TestImages.discOnClear(side: 32))
        let png = try CharmImageProcessor.encodePNG(image)
        return ProcessedCharmImage(
            pngData: png,
            pixelSide: 32,
            metrics: CharmMetrics(mass: 3, radiusRatio: 0.12, knotInset: 0.9),
            palette: .derived(from: CharmColor(0.9, 0.2, 0.2))
        )
    }

    @Test("Adding writes the bitmap and the manifest")
    func addPersists() throws {
        let directory = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CustomCharmStore(directory: directory)
        let entry = try store.add(makeProcessed(), name: "Disc")

        #expect(store.entries.count == 1)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: entry.imageFileName).path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "manifest.json").path))
    }

    @Test("A fresh store over the same directory sees the entry and can load its bitmap")
    func reloads() throws {
        let directory = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let entry = try CustomCharmStore(directory: directory).add(makeProcessed(), name: "Disc")

        let reloaded = CustomCharmStore(directory: directory)
        let charm = try #require(reloaded.charm(for: entry.id))

        #expect(reloaded.entries == [entry])
        #expect(charm.id == .custom(entry.id))
        #expect(charm.displayName == "Disc")
        #expect(charm.bitmap.width == 32)
        #expect(charm.artwork().bitmap != nil)
        #expect(charm.metrics.mass == 3)
    }

    @Test("Removing deletes the bitmap and forgets the entry")
    func removeCleansUp() throws {
        let directory = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CustomCharmStore(directory: directory)
        let entry = try store.add(makeProcessed(), name: "Disc")
        try store.remove(id: entry.id)

        #expect(store.entries.isEmpty)
        #expect(store.charm(for: entry.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: entry.imageFileName).path))
        #expect(CustomCharmStore(directory: directory).entries.isEmpty)
    }

    @Test("An entry whose bitmap has vanished is dropped on load")
    func prunesMissingBitmaps() throws {
        let directory = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let entry = try CustomCharmStore(directory: directory).add(makeProcessed(), name: "Disc")
        try FileManager.default.removeItem(at: directory.appending(path: entry.imageFileName))

        #expect(CustomCharmStore(directory: directory).entries.isEmpty)
    }

    @Test("A corrupt manifest is moved aside, not overwritten, and its charms are recovered")
    func recoversFromCorruptManifest() throws {
        let directory = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A healthy store with one charm, then the manifest is trashed.
        let entry = try CustomCharmStore(directory: directory).add(makeProcessed(), name: "Disc")
        try Data("not json".utf8).write(to: directory.appending(path: "manifest.json"))

        let store = CustomCharmStore(directory: directory)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("manifest.corrupt-") })
        #expect(store.recoveredCount == 1)
        #expect(store.entries.count == 1)
        // The recovered entry keeps the bitmap's UUID, so identity survives.
        #expect(store.entries.first?.id == entry.id)
        #expect(store.charm(for: entry.id)?.bitmap.width == 32)
        // And the repaired manifest is readable next time.
        #expect(CustomCharmStore(directory: directory).entries.count == 1)
    }

    @Test("A bitmap copied into the folder by hand becomes a charm")
    func recoversOrphanedBitmap() throws {
        let directory = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeProcessed().pngData.write(to: directory.appending(path: "loose.png"))

        let store = CustomCharmStore(directory: directory)

        #expect(store.entries.count == 1)
        #expect(store.entries.first?.name.hasPrefix("Recovered charm") == true)
        #expect(store.entries.first?.metrics.mass ?? 0 > 0)
    }

    @Test("A pruned entry is reported so the selection can move off it")
    func reportsPrunedEntries() throws {
        let directory = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let entry = try CustomCharmStore(directory: directory).add(makeProcessed(), name: "Disc")
        try FileManager.default.removeItem(at: directory.appending(path: entry.imageFileName))

        let store = CustomCharmStore(directory: directory)
        #expect(store.prunedIDs == [entry.id])
        #expect(store.entries.isEmpty)
    }

    @Test("There is no cap on how many charms are stored")
    func storesMany() throws {
        let directory = try TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CustomCharmStore(directory: directory)
        for index in 0..<40 {
            _ = try store.add(makeProcessed(), name: "Charm \(index)")
        }

        #expect(store.entries.count == 40)
        #expect(CustomCharmStore(directory: directory).entries.count == 40)
    }
}

/// Import and delete through the manager, which is what the menu and a drop use.
@Suite("Charm import")
@MainActor
struct CharmImportTests {
    private struct Fixture {
        let manager: CharmManager
        let store: CustomCharmStore
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
        let store = CustomCharmStore(directory: directory.appending(path: "charms"))
        let manager = CharmManager(
            settingsStore: SettingsStore(defaults: defaults, storageKey: "settings"),
            customStore: store
        )
        return Fixture(manager: manager, store: store, defaults: defaults, suiteName: suiteName, directory: directory)
    }

    @Test("Importing stores the charm, selects it, and lists it in the menu")
    func importSelectsTheNewCharm() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let disc = try #require(TestImages.discOnWhite())
        let url = fixture.directory.appending(path: "My Photo.png")
        try TestImages.write(disc, as: .png, to: url)

        try await fixture.manager.importImage(at: url, name: "My Photo")

        let entry = try #require(fixture.store.entries.first)
        #expect(fixture.manager.selection == .custom(entry.id))
        #expect(fixture.manager.current.displayName == "My Photo")
        #expect(fixture.manager.current.artwork().bitmap != nil)
        #expect(fixture.manager.canDeleteCurrent)
        #expect(fixture.manager.menuItems.last?.id == .custom(entry.id))
        #expect(fixture.manager.isImporting == false)
    }

    @Test("Deleting the selected import puts the circle back on the rope")
    func deleteFallsBackToCircle() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let disc = try #require(TestImages.discOnWhite())
        let url = fixture.directory.appending(path: "disc.png")
        try TestImages.write(disc, as: .png, to: url)
        try await fixture.manager.importImage(at: url, name: "Disc")
        let id = try #require(fixture.store.entries.first?.id)

        try fixture.manager.deleteCharm(id: id)

        #expect(fixture.manager.selection == .builtIn(.circle))
        #expect(fixture.store.entries.isEmpty)
        #expect(fixture.manager.menuItems.count == BuiltInCharms.all.count)
    }

    @Test("An unreadable file fails cleanly and changes nothing")
    func failedImportLeavesStateAlone() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let url = fixture.directory.appending(path: "broken.png")
        try Data("not an image".utf8).write(to: url)

        await #expect(throws: CharmImageError.self) {
            try await fixture.manager.importImage(at: url, name: "Broken")
        }
        #expect(fixture.store.entries.isEmpty)
        #expect(fixture.manager.selection == OverlaySettings().charm)
        #expect(fixture.manager.isImporting == false)
    }
}
