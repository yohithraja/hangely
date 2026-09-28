//
//  CharmLibraryTests.swift
//  HanglyTests
//

import AppKit
import Foundation
import Testing

@testable import Hangly

/// The metadata document is the Library's source of words, so its agreement with
/// the code — every kind present, names matching, categories real — is asserted.
@Suite("Charm library document")
struct CharmLibraryDocumentTests {
    private let library = CharmLibrary.bundled()

    @Test("The bundled document loads with every built-in charm in it")
    func coversEveryKind() {
        #expect(library.entries.count == CharmKind.allCases.count)
        for kind in CharmKind.allCases {
            #expect(library.entry(for: kind) != nil, "missing entry for \(kind.rawValue)")
        }
    }

    @Test("The document and the code agree on every charm's name")
    func namesMatchCode() {
        for kind in CharmKind.allCases {
            #expect(library.entry(for: kind)?.name == kind.displayName)
        }
    }

    @Test("Every entry is complete and points at a real category")
    func entriesAreComplete() {
        let categoryIDs = Set(library.categories.map(\.id))
        #expect(!categoryIDs.isEmpty)

        for entry in library.entries {
            #expect(!entry.name.isEmpty)
            #expect(!entry.region.isEmpty)
            #expect(entry.description.count > 40, "\(entry.id) needs a real description")
            #expect(!entry.tags.isEmpty)
            #expect(categoryIDs.contains(entry.category), "\(entry.id) has unknown category \(entry.category)")
            #expect(entry.previewImage == "charm-preview-\(entry.id)")
        }
    }

    @Test("Every charm has a preview image in the asset catalog")
    func previewAssetsExist() {
        for entry in CharmLibrary.bundled().entries {
            #expect(NSImage(named: entry.previewImage) != nil, "missing asset \(entry.previewImage)")
        }
    }

    @Test("The eleven collection charms are all present")
    func collectionIsComplete() {
        let collection: Set<CharmKind> = [
            .nazar, .hamsa, .nimbuMirchi, .ghanta, .drishtiBommai, .panchangJie,
            .daruma, .manekiNeko, .horseshoe, .scarab, .himmeli
        ]
        for kind in collection {
            #expect(BuiltInCharms.charm(for: kind).id == .builtIn(kind))
            #expect(library.entry(for: kind) != nil)
        }
    }

    @Test("A broken document yields an empty library rather than a crash")
    func toleratesBrokenDocument() {
        #expect(throws: (any Error).self) {
            try CharmLibrary(data: Data("nope".utf8))
        }
        let empty = CharmLibrary.bundled(in: Bundle(for: NSApplication.self))
        #expect(empty.entries.isEmpty)
    }
}

/// The browser's filtering, selection and favourites, against real settings and
/// a throwaway charm directory.
@Suite("Charm library browser")
@MainActor
struct CharmLibraryViewModelTests {
    private struct Fixture {
        let viewModel: CharmLibraryViewModel
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
        let manager = CharmManager(
            settingsStore: SettingsStore(defaults: defaults, storageKey: "settings"),
            customStore: CustomCharmStore(directory: directory)
        )
        let studio = CharmStudioWindowController(
            viewModel: CharmStudioViewModel(charmManager: manager, accessibility: AccessibilityPreferences())
        )
        let viewModel = CharmLibraryViewModel(
            library: .bundled(),
            charmManager: manager,
            importCoordinator: CharmImportCoordinator(charmManager: manager, dialogs: CharmDialogs(), studio: studio)
        )
        return Fixture(
            viewModel: viewModel,
            manager: manager,
            defaults: defaults,
            suiteName: suiteName,
            directory: directory
        )
    }

    @Test("Everything is listed by default, in document order")
    func listsEverything() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        #expect(fixture.viewModel.items.count == CharmKind.allCases.count)
        #expect(fixture.viewModel.items.first?.id == .builtIn(.nazar))
        #expect(fixture.viewModel.hasCustomCharms == false)
    }

    @Test("Search matches names, regions, tags and descriptions, ignoring accents and case")
    func searchIsForgiving() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.viewModel.searchText = "PANCHANG"
        #expect(fixture.viewModel.items.map(\.id) == [.builtIn(.panchangJie)])

        fixture.viewModel.searchText = "evil eye"
        let evilEye = Set(fixture.viewModel.items.map(\.id))
        #expect(evilEye.contains(.builtIn(.nazar)))
        #expect(evilEye.contains(.builtIn(.nimbuMirchi)))
        #expect(evilEye.contains(.builtIn(.drishtiBommai)))

        fixture.viewModel.searchText = "japan"
        #expect(Set(fixture.viewModel.items.map(\.id)) == [.builtIn(.daruma), .builtIn(.manekiNeko)])

        fixture.viewModel.searchText = "zzzz"
        #expect(fixture.viewModel.items.isEmpty)
    }

    @Test("Category filters partition the collection")
    func categoriesFilter() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        var counted = 0
        for category in fixture.viewModel.categories {
            fixture.viewModel.filter = .category(category.id)
            let items = fixture.viewModel.items
            #expect(!items.isEmpty, "category \(category.id) is empty")
            #expect(items.allSatisfy { $0.categoryID == category.id })
            counted += items.count
        }
        #expect(counted == CharmKind.allCases.count)
    }

    @Test("Selecting a card puts it on the rope at once")
    func selectionSwitchesTheRope() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.viewModel.select(.builtIn(.scarab))

        #expect(fixture.manager.selection == .builtIn(.scarab))
        #expect(fixture.viewModel.selectedItem?.name == "Scarab")
        #expect(fixture.viewModel.isSelected(.builtIn(.scarab)))
    }

    @Test("Favourites toggle, filter and persist across a reload")
    func favoritesPersist() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.viewModel.toggleFavorite(.builtIn(.hamsa))
        fixture.viewModel.toggleFavorite(.builtIn(.himmeli))
        fixture.viewModel.filter = .favorites

        #expect(fixture.viewModel.favoriteCount == 2)
        #expect(Set(fixture.viewModel.items.map(\.id)) == [.builtIn(.hamsa), .builtIn(.himmeli)])

        fixture.viewModel.toggleFavorite(.builtIn(.hamsa))
        #expect(fixture.viewModel.items.map(\.id) == [.builtIn(.himmeli)])

        let reloaded = SettingsStore(defaults: fixture.defaults, storageKey: "settings")
        #expect(reloaded.settings.favoriteCharms == [.builtIn(.himmeli)])
    }

    @Test("An unrecognised favourite is dropped on its own, keeping the rest")
    func unknownFavoriteIsDropped() throws {
        let json = #"{"favoriteCharms": ["star", "sparkle", "custom:nope"]}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        #expect(decoded.favoriteCharms == [.builtIn(.star)])
    }

    @Test("Imports appear under Yours and leave with their favourite star")
    func importsAppearUnderYours() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        let disc = try #require(TestImages.discOnWhite())
        let url = fixture.directory.appending(path: "mine.png")
        try TestImages.write(disc, as: .png, to: url)
        try await fixture.manager.importImage(at: url, name: "Mine")
        let id = try #require(fixture.viewModel.allItems.last?.id)

        #expect(fixture.viewModel.hasCustomCharms)
        fixture.viewModel.filter = .yours
        #expect(fixture.viewModel.items.map(\.name) == ["Mine"])
        #expect(fixture.viewModel.selectedItem?.isCustom == true)

        fixture.viewModel.toggleFavorite(id)
        #expect(fixture.viewModel.isFavorite(id))

        guard case .custom(let uuid) = id else { return }
        try fixture.manager.deleteCharm(id: uuid)

        #expect(fixture.viewModel.hasCustomCharms == false)
        #expect(fixture.viewModel.favoriteCount == 0)
        #expect(fixture.manager.selection == .builtIn(.circle))
    }
}
