//
//  CustomCharmStore.swift
//  Hangly
//
//  On-disk home for imported charms.
//

import CoreGraphics
import Foundation
import ImageIO
import Observation
import OSLog

/// Persists imported charms as processed PNGs plus a JSON manifest.
///
/// Layout, under Application Support:
///
/// ```
/// Hangly/Charms/
///   manifest.json      every entry's name, metrics and palette
///   <uuid>.png         the processed, background-removed square bitmap
/// ```
///
/// Bitmaps are loaded lazily and cached, so listing a hundred imports in the menu
/// costs nothing and memory grows only with charms actually shown. The manifest is
/// the source of truth; an entry whose PNG has gone missing is dropped at load so a
/// stale reference can never leave the rope bare.
@MainActor
@Observable
final class CustomCharmStore {
    /// Imported charms, oldest first.
    private(set) var entries: [CustomCharmEntry] = []

    /// Entries dropped at load because their bitmap was gone. The charm manager
    /// uses this to move the selection off a charm that no longer exists.
    private(set) var prunedIDs: Set<UUID> = []

    /// Bitmaps found on disk with no manifest entry, re-registered at load.
    private(set) var recoveredCount = 0

    let directory: URL

    @ObservationIgnored private var bitmapCache: [UUID: CGImage] = [:]
    @ObservationIgnored private let fileManager = FileManager.default

    private static let manifestName = "manifest.json"

    /// `~/Library/Application Support/<bundle id>/Charms`.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: AppConstants.bundleIdentifier).appending(path: "Charms")
    }

    /// - Parameter directory: Injected so tests can use a throwaway location.
    init(directory: URL = CustomCharmStore.defaultDirectory) {
        self.directory = directory
        loadManifest()
    }

    // MARK: - Mutation

    /// Writes the bitmap and records the entry. The new entry is returned so the
    /// caller can select it.
    func add(_ processed: ProcessedCharmImage, name: String) throws -> CustomCharmEntry {
        try ensureDirectory()

        let id = UUID()
        let fileName = "\(id.uuidString).png"
        try processed.pngData.write(to: directory.appending(path: fileName), options: .atomic)

        // Whole seconds: the manifest stores ISO 8601 without fractions, and an
        // entry must compare equal to itself after a reload.
        let createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let entry = CustomCharmEntry(
            id: id,
            name: name,
            createdAt: createdAt,
            imageFileName: fileName,
            metrics: processed.metrics,
            palette: processed.palette
        )
        entries.append(entry)
        try saveManifest()

        Logger.overlay.diagnostic("Stored custom charm \(name).")
        return entry
    }

    /// Removes the entry and its bitmap. Removing something absent is not an error.
    func remove(id: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }

        let entry = entries.remove(at: index)
        bitmapCache[id] = nil

        let url = directory.appending(path: entry.imageFileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try saveManifest()

        Logger.overlay.diagnostic("Deleted custom charm \(entry.name).")
    }

    // MARK: - Reading

    func entry(for id: UUID) -> CustomCharmEntry? {
        entries.first { $0.id == id }
    }

    /// The charm with its bitmap loaded. `nil` when the entry or its file is gone.
    func charm(for id: UUID) -> CustomCharm? {
        guard let entry = entry(for: id) else { return nil }

        if let cached = bitmapCache[id] {
            return CustomCharm(entry: entry, bitmap: cached)
        }
        guard let bitmap = loadBitmap(named: entry.imageFileName) else {
            Logger.overlay.error("Bitmap missing for charm \(entry.name, privacy: .public).")
            return nil
        }
        bitmapCache[id] = bitmap
        return CustomCharm(entry: entry, bitmap: bitmap)
    }

    // MARK: - Files

    private var manifestURL: URL {
        directory.appending(path: Self.manifestName)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func loadBitmap(named fileName: String) -> CGImage? {
        let url = directory.appending(path: fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    }

    /// Reads the manifest, then repairs whatever it can.
    ///
    /// Three failures are handled, each without losing anything recoverable:
    /// an unreadable manifest is moved aside with a timestamp rather than
    /// overwritten; an entry whose bitmap has vanished is dropped and reported; and
    /// a bitmap with no entry — the result of either of the above, or of a manual
    /// copy into the folder — is analysed and re-registered.
    private func loadManifest() {
        entries = decodeManifest()
        pruneMissingBitmaps()
        recoverOrphanedBitmaps()
    }

    private func decodeManifest() -> [CustomCharmEntry] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([CustomCharmEntry].self, from: data)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = directory.appending(path: "manifest.corrupt-\(stamp).json")
            try? fileManager.moveItem(at: manifestURL, to: backup)
            Logger.overlay.error("Unreadable charm manifest moved to \(backup.lastPathComponent, privacy: .public).")
            return []
        }
    }

    private func pruneMissingBitmaps() {
        let missing = entries.filter { entry in
            !fileManager.fileExists(atPath: directory.appending(path: entry.imageFileName).path)
        }
        guard !missing.isEmpty else { return }

        for entry in missing {
            Logger.overlay.warning("Dropping charm \(entry.name, privacy: .public): bitmap missing.")
        }
        prunedIDs = Set(missing.map(\.id))
        entries.removeAll { prunedIDs.contains($0.id) }
        try? saveManifest()
    }

    private func recoverOrphanedBitmaps() {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        let known = Set(entries.map(\.imageFileName))
        let orphans = files
            .filter { $0.pathExtension.lowercased() == "png" && !known.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !orphans.isEmpty else { return }

        for (index, url) in orphans.enumerated() {
            guard let bitmap = loadBitmap(named: url.lastPathComponent),
                  let analysis = try? CharmImageProcessor.analyze(bitmap) else {
                Logger.overlay.warning("Could not recover \(url.lastPathComponent, privacy: .public); skipping.")
                continue
            }
            // Reuse the file's UUID name where it has one, so a re-run is stable.
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            entries.append(CustomCharmEntry(
                id: id,
                name: "Recovered charm \(index + 1)",
                createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
                imageFileName: url.lastPathComponent,
                metrics: analysis.metrics,
                palette: analysis.palette
            ))
            recoveredCount += 1
        }
        if recoveredCount > 0 {
            Logger.overlay.diagnostic("Recovered \(self.recoveredCount) charm bitmap(s) into the manifest.")
            try? saveManifest()
        }
    }

    private func saveManifest() throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: manifestURL, options: .atomic)
    }
}
