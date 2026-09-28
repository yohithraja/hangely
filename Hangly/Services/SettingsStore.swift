//
//  SettingsStore.swift
//  Hangly
//
//  Observable, persisted home for `AppSettings`.
//

import Foundation
import Observation
import OSLog

/// Single source of truth for user preferences.
///
/// Every write goes through one funnel — the `settings` setter — which is what makes
/// autosave reliable: SwiftUI bindings, the menu bar toggle and programmatic updates
/// all persist through the same path, with no `didSet` and no manual "save" call.
///
/// The store is `@Observable`, so SwiftUI views re-render automatically and services
/// can subscribe through `ObservationStream`.
@MainActor
@Observable
final class SettingsStore {
    /// The current settings. Assigning persists the new value if it actually changed.
    var settings: AppSettings {
        get {
            access(keyPath: \.settings)
            return storage
        }
        set {
            guard newValue != storage else { return }
            withMutation(keyPath: \.settings) { storage = newValue }
            persist(newValue)
        }
    }

    /// Whether this launch found no settings document — a first run, or a run after
    /// the document was removed. The shipped defaults are all that is known about
    /// what the user wants, which is the one moment it is right to act on them.
    @ObservationIgnored private(set) var isFirstRun = false

    @ObservationIgnored private var storage: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    /// - Parameters:
    ///   - defaults: Injected so tests can use a throwaway suite.
    ///   - storageKey: Versioned key, see `AppConstants.Defaults`.
    init(
        defaults: UserDefaults = .standard,
        storageKey: String = AppConstants.Defaults.settingsStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.storage = AppSettings()

        if let loaded = load() {
            self.storage = loaded
        } else {
            self.isFirstRun = true
        }
    }

    /// Applies an in-place edit. Preferred over read-modify-write at the call site
    /// because it keeps the change atomic and triggers exactly one save.
    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
    }

    /// Restores every preference to its shipped default.
    func resetToDefaults() {
        settings = AppSettings()
    }

    /// Writes the current settings out even if nothing changed.
    ///
    /// Ordinary edits persist themselves through the setter. This exists for the
    /// first run, where the defaults are already correct and so would never be
    /// written — leaving the next launch to think it was a first run too, and to
    /// apply the defaults over whatever the user had since chosen.
    func save() {
        persist(storage)
        isFirstRun = false
    }

    // MARK: - Persistence

    /// Where an unreadable document is kept, so nothing the user chose is lost
    /// without a trace.
    var backupKey: String {
        storageKey + ".corrupt"
    }

    private func load() -> AppSettings? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            // A corrupt document must never block launch: keep a copy, then fall
            // back to defaults.
            Logger.settings.error("Unreadable settings kept at \(self.backupKey, privacy: .public); using defaults.")
            defaults.set(data, forKey: backupKey)
            defaults.removeObject(forKey: storageKey)
            return nil
        }
    }

    private func persist(_ value: AppSettings) {
        do {
            let data = try encoder.encode(value)
            defaults.set(data, forKey: storageKey)
        } catch {
            Logger.settings.error("Failed to persist settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
