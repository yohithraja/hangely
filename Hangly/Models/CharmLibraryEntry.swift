//
//  CharmLibraryEntry.swift
//  Hangly
//
//  What the metadata document says about a built-in charm.
//

import Foundation

/// A group in the Library sidebar.
struct CharmCategory: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
}

/// Everything the Library shows about a built-in charm that is not geometry.
///
/// Geometry stays in Swift, where it can be typed and tested; words live in JSON,
/// where they can be edited, reviewed and one day translated without a rebuild.
/// `id` is the `CharmKind` raw value, and a test insists that every kind has an
/// entry and that the two agree on the name.
struct CharmLibraryEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let region: String
    let category: String
    let description: String
    let tags: [String]
    let previewImage: String

    var kind: CharmKind? {
        CharmKind(rawValue: id)
    }
}

/// The top level of `CharmLibrary.json`.
struct CharmLibraryDocument: Codable, Sendable {
    let version: Int
    let categories: [CharmCategory]
    let charms: [CharmLibraryEntry]
}
