//
//  CharmManager.swift
//  Hangly
//
//  The charm registry and the current selection.
//

import Foundation
import Observation
import OSLog

/// What the menu needs to list a charm: no geometry, no bitmap.
struct CharmMenuItem: Identifiable, Hashable, Sendable {
    let id: CharmID
    let name: String
    let symbolName: String
}

/// Owns which charm is on the rope and the set it can be chosen from.
///
/// The set is the built-ins followed by every import, and it changes at runtime:
/// an import appends, a deletion removes, and because the store is observable the
/// menu follows without being told. The selection lives in `SettingsStore`, so it
/// persists and survives a relaunch. Switching is live either way: the overlay
/// notices on its next frame and cross-fades, with nothing to restart.
@MainActor
@Observable
final class CharmManager {
    /// Set for the duration of an import, so the overlay can show progress and a
    /// second import is refused rather than raced.
    private(set) var isImporting = false

    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let customStore: CustomCharmStore

    init(settingsStore: SettingsStore, customStore: CustomCharmStore) {
        self.settingsStore = settingsStore
        self.customStore = customStore
        reconcile()
    }

    /// A settings document can outlive the charms it names: the store pruned one,
    /// or its folder was cleared by hand. Rather than leave the rope quietly on a
    /// fallback while the document still points at a ghost, move the selection and
    /// drop the star, once, at launch.
    private func reconcile() {
        let settings = settingsStore.settings
        let ghosts = settings.favoriteCharms.filter { id in
            if case .custom(let uuid) = id { return customStore.entry(for: uuid) == nil }
            return false
        }
        var selectionIsGhost = false
        if case .custom(let uuid) = settings.overlay.charm, customStore.entry(for: uuid) == nil {
            selectionIsGhost = true
        }
        guard selectionIsGhost || !ghosts.isEmpty else { return }

        settingsStore.update { settings in
            settings.favoriteCharms.subtract(ghosts)
            if selectionIsGhost {
                settings.overlay.charm = .builtIn(.circle)
            }
        }
        let detail = selectionIsGhost ? ", selection reset" : ""
        Logger.overlay.warning("Reconciled settings: \(ghosts.count) missing favourite(s)\(detail, privacy: .public).")
    }

    // MARK: - Selection

    /// The selected charm's identity. Setting it persists immediately.
    var selection: CharmID {
        get { settingsStore.settings.overlay.charm }
        set {
            guard newValue != settingsStore.settings.overlay.charm else { return }
            settingsStore.update { $0.overlay.charm = newValue }
            Logger.overlay.diagnostic("Charm changed to \(newValue.storageValue).")
        }
    }

    /// The charm currently on the rope.
    var current: any Charm {
        charm(for: selection)
    }

    /// Only imports can be deleted; the built-ins are permanent.
    var canDeleteCurrent: Bool {
        selection.isCustom
    }

    // MARK: - Registry

    /// Built-ins first, then imports oldest to newest.
    var menuItems: [CharmMenuItem] {
        let builtIns = BuiltInCharms.all.map {
            CharmMenuItem(id: $0.id, name: $0.displayName, symbolName: $0.symbolName)
        }
        let customs = customStore.entries.map {
            CharmMenuItem(id: .custom($0.id), name: $0.name, symbolName: "photo.fill")
        }
        return builtIns + customs
    }

    var customEntries: [CustomCharmEntry] {
        customStore.entries
    }

    func customEntry(for id: UUID) -> CustomCharmEntry? {
        customStore.entry(for: id)
    }

    /// Resolves any identity to a charm. An import that has been deleted or whose
    /// file has gone falls back to the circle rather than to nothing.
    func charm(for id: CharmID) -> any Charm {
        switch id {
        case .builtIn(let kind):
            return BuiltInCharms.charm(for: kind)
        case .custom(let uuid):
            return customStore.charm(for: uuid) ?? CircleCharm()
        }
    }

    // MARK: - Import and delete

    /// Processes the file off the main actor, stores the result and selects it.
    /// The quick path; the Studio produces the same `ProcessedCharmImage` with the
    /// user watching, then calls `saveImport`.
    func importImage(at url: URL, name: String) async throws {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let processed = try await CharmImageProcessor.process(fileAt: url)
        try saveImport(processed, name: name, select: true)
    }

    /// Stores a processed image as a charm.
    /// - Parameter select: Whether to put it on the rope straight away.
    @discardableResult
    func saveImport(_ processed: ProcessedCharmImage, name: String, select: Bool) throws -> CustomCharmEntry {
        let entry = try customStore.add(processed, name: name)
        if select {
            selection = .custom(entry.id)
        }
        return entry
    }

    /// Removes an import. If it was on the rope, the circle takes its place.
    func deleteCharm(id: UUID) throws {
        try customStore.remove(id: id)
        settingsStore.update { settings in
            settings.favoriteCharms.remove(.custom(id))
            if settings.overlay.charm == .custom(id) {
                settings.overlay.charm = .builtIn(.circle)
            }
        }
    }

    // MARK: - Favourites

    func isFavorite(_ id: CharmID) -> Bool {
        settingsStore.settings.favoriteCharms.contains(id)
    }

    func toggleFavorite(_ id: CharmID) {
        settingsStore.update { settings in
            if settings.favoriteCharms.contains(id) {
                settings.favoriteCharms.remove(id)
            } else {
                settings.favoriteCharms.insert(id)
            }
        }
    }

    var favoriteCount: Int {
        settingsStore.settings.favoriteCharms.count
    }
}
