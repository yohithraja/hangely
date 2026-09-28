//
//  CharmLibraryViewModel.swift
//  Hangly
//
//  Presentation state for the Charm Library window.
//

import Foundation
import Observation

/// One row of the Library: a built-in from the metadata document, or an import.
struct CharmLibraryItem: Identifiable, Hashable, Sendable {
    let id: CharmID
    let name: String
    let region: String
    let description: String
    let tags: [String]
    let categoryID: String

    var isCustom: Bool { id.isCustom }

    /// The words search looks through, folded once so filtering is cheap.
    var searchText: String {
        ([name, region, description] + tags).joined(separator: " ").searchFolded
    }
}

/// Backs `CharmLibraryView`.
///
/// Built-ins come from `CharmLibrary`; imports come from the charm manager and are
/// given a synthetic "Yours" category. Search folds case and diacritics so
/// "pancha" finds "Pánchángjié". Selecting an item puts it on the rope immediately;
/// there is no separate apply step, because the overlay is the preview.
@MainActor
@Observable
final class CharmLibraryViewModel {
    enum Filter: Hashable {
        case all
        case favorites
        case category(String)
        case yours
    }

    /// Identifier used for imports in the sidebar.
    static let yoursCategoryID = "yours"

    var searchText = ""
    var filter: Filter = .all

    @ObservationIgnored private let library: CharmLibrary
    @ObservationIgnored private let charmManager: CharmManager
    @ObservationIgnored private let importCoordinator: CharmImportCoordinator

    init(library: CharmLibrary, charmManager: CharmManager, importCoordinator: CharmImportCoordinator) {
        self.library = library
        self.charmManager = charmManager
        self.importCoordinator = importCoordinator
    }

    // MARK: - Catalogue

    var categories: [CharmCategory] {
        library.categories
    }

    /// Every charm the Library knows about, built-ins in document order then imports.
    var allItems: [CharmLibraryItem] {
        let builtIns = library.entries.map { entry in
            CharmLibraryItem(
                id: .builtIn(entry.kind ?? .circle),
                name: entry.name,
                region: entry.region,
                description: entry.description,
                tags: entry.tags,
                categoryID: entry.category
            )
        }
        let customs = charmManager.customEntries.map { entry in
            CharmLibraryItem(
                id: .custom(entry.id),
                name: entry.name,
                region: "Yours",
                description: "Imported from your own image.",
                tags: ["imported", "custom"],
                categoryID: Self.yoursCategoryID
            )
        }
        return builtIns + customs
    }

    /// `allItems` after the sidebar filter and the search field.
    var items: [CharmLibraryItem] {
        let query = searchText.searchFolded
        return allItems.filter { item in
            matches(filter: filter, item: item) && (query.isEmpty || item.searchText.contains(query))
        }
    }

    var hasCustomCharms: Bool {
        !charmManager.customEntries.isEmpty
    }

    var favoriteCount: Int {
        charmManager.favoriteCount
    }

    private func matches(filter: Filter, item: CharmLibraryItem) -> Bool {
        switch filter {
        case .all: true
        case .favorites: charmManager.isFavorite(item.id)
        case .category(let id): item.categoryID == id
        case .yours: item.isCustom
        }
    }

    // MARK: - Selection

    /// The charm on the rope. The detail pane always shows this one.
    var selectedID: CharmID {
        charmManager.selection
    }

    var selectedItem: CharmLibraryItem? {
        allItems.first { $0.id == selectedID }
    }

    func isSelected(_ id: CharmID) -> Bool {
        id == selectedID
    }

    /// One click: the rope changes on its next frame.
    func select(_ id: CharmID) {
        charmManager.selection = id
    }

    func charm(for id: CharmID) -> any Charm {
        charmManager.charm(for: id)
    }

    // MARK: - Favourites

    func isFavorite(_ id: CharmID) -> Bool {
        charmManager.isFavorite(id)
    }

    func toggleFavorite(_ id: CharmID) {
        charmManager.toggleFavorite(id)
    }

    // MARK: - Imports

    var isImporting: Bool {
        charmManager.isImporting
    }

    var canDeleteSelected: Bool {
        charmManager.canDeleteCurrent
    }

    func importImage() {
        importCoordinator.importFromOpenPanel()
    }

    func deleteSelected() {
        importCoordinator.deleteCurrentCharm()
    }
}

extension String {
    /// Lowercased with diacritics stripped, for search.
    var searchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
