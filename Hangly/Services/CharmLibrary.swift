//
//  CharmLibrary.swift
//  Hangly
//
//  Loads the charm metadata document.
//

import Foundation
import OSLog

/// The bundled charm metadata, decoded once.
///
/// Immutable after load, so it is a plain `Sendable` value rather than an
/// observable object. A missing or unreadable document is logged and yields an
/// empty library rather than a crash: the rope still works, the Library window is
/// merely sparse.
struct CharmLibrary: Sendable {
    static let resourceName = "CharmLibrary"

    let categories: [CharmCategory]
    let entries: [CharmLibraryEntry]

    private let byID: [String: CharmLibraryEntry]

    init(document: CharmLibraryDocument) {
        categories = document.categories
        entries = document.charms
        byID = Dictionary(document.charms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(data: Data) throws {
        self.init(document: try JSONDecoder().decode(CharmLibraryDocument.self, from: data))
    }

    /// Reads `CharmLibrary.json` from the given bundle.
    static func bundled(in bundle: Bundle = .main) -> CharmLibrary {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            Logger.app.error("CharmLibrary.json is missing from the bundle.")
            return CharmLibrary(document: CharmLibraryDocument(version: 0, categories: [], charms: []))
        }
        do {
            return try CharmLibrary(data: Data(contentsOf: url))
        } catch {
            Logger.app.error("CharmLibrary.json is unreadable: \(error.localizedDescription, privacy: .public)")
            return CharmLibrary(document: CharmLibraryDocument(version: 0, categories: [], charms: []))
        }
    }

    func entry(for kind: CharmKind) -> CharmLibraryEntry? {
        byID[kind.rawValue]
    }

    func category(id: String) -> CharmCategory? {
        categories.first { $0.id == id }
    }
}
