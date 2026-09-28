//
//  SettingsStoreTests.swift
//  HanglyTests
//

import Foundation
import Testing

@testable import Hangly

/// Exercises the real store against a throwaway `UserDefaults` suite, which is only
/// possible because the suite is injected rather than reached for as a global.
@Suite("Settings store")
@MainActor
struct SettingsStoreTests {
    /// A fresh, isolated defaults suite per test.
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "com.hangly.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @Test("A store with no saved document starts at the defaults")
    func startsAtDefaults() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, storageKey: "settings")

        #expect(store.settings == AppSettings())
    }

    @Test("A store knows whether it found a document, and stops saying so once it saves")
    func firstRunIsReported() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = SettingsStore(defaults: defaults, storageKey: "settings")
        #expect(fresh.isFirstRun)

        // Committing unchanged defaults is the whole point: without it the next
        // launch would see no document and treat itself as a first run too.
        fresh.save()
        #expect(fresh.isFirstRun == false)

        let reopened = SettingsStore(defaults: defaults, storageKey: "settings")
        #expect(reopened.isFirstRun == false)
        #expect(reopened.settings == AppSettings())
    }

    @Test("An ordinary edit is enough to mark the document as written")
    func editsPersistWithoutAnExplicitSave() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, storageKey: "settings")
        store.update { $0.overlay.opacity = 0.5 }

        #expect(SettingsStore(defaults: defaults, storageKey: "settings").isFirstRun == false)
    }

    @Test("Changes survive being reloaded by a new store")
    func changesArePersisted() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, storageKey: "settings")
        store.update {
            $0.overlay.anchor = .topTrailing
            $0.overlay.opacity = 0.42
        }

        let reloaded = SettingsStore(defaults: defaults, storageKey: "settings")

        #expect(reloaded.settings.overlay.anchor == .topTrailing)
        #expect(reloaded.settings.overlay.opacity == 0.42)
    }

    @Test("Assigning an unchanged value writes nothing")
    func redundantWritesAreSkipped() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, storageKey: "settings")
        // Nothing has been written yet, so a no-op assignment must not create a document.
        store.settings = store.settings

        #expect(defaults.data(forKey: "settings") == nil)
    }

    @Test("Resetting restores every default and persists the reset")
    func resetRestoresDefaults() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults, storageKey: "settings")
        store.update { $0.overlay.scale = 1.75 }
        store.resetToDefaults()

        let reloaded = SettingsStore(defaults: defaults, storageKey: "settings")

        #expect(store.settings == AppSettings())
        #expect(reloaded.settings == AppSettings())
    }

    @Test("A corrupt document falls back to defaults instead of failing to launch")
    func corruptDocumentFallsBackToDefaults() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not json".utf8), forKey: "settings")
        let store = SettingsStore(defaults: defaults, storageKey: "settings")

        #expect(store.settings == AppSettings())
        // The unreadable bytes are kept aside rather than destroyed.
        #expect(defaults.data(forKey: store.backupKey) == Data("not json".utf8))
        #expect(defaults.data(forKey: "settings") == nil)
    }
}
