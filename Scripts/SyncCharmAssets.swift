//
//  SyncCharmAssets.swift
//  Hangly
//
//  Copies the designer's SVGs from Assets/Charms into the asset catalog as
//  vector-preserving imagesets, one per collection charm, and reports anything
//  that does not line up. Run via Scripts/sync-charm-assets.sh.
//

import Foundation

@main
struct SyncCharmAssets {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: sync <Assets/Charms dir> <CharmArtwork catalog dir>\n".utf8))
            exit(2)
        }
        let sourceDirectory = URL(fileURLWithPath: arguments[0])
        let catalog = URL(fileURLWithPath: arguments[1])
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: catalog, withIntermediateDirectories: true)
        try writeJSON(["info": ["author": "xcode", "version": 1]], to: catalog.appending(path: "Contents.json"))

        var missing: [String] = []
        var mapped: Set<String> = []

        for entry in CollectionCharmCatalog.entries {
            let source = sourceDirectory.appending(path: entry.sourceFileName)
            guard fileManager.fileExists(atPath: source.path) else {
                missing.append("\(entry.kind.rawValue) ← \(entry.sourceFileName)")
                continue
            }
            mapped.insert(entry.sourceFileName)

            let name = SVGArtworkSource.assetName(for: entry.kind)
            let imageset = catalog.appending(path: "\(name).imageset")
            try? fileManager.removeItem(at: imageset)
            try fileManager.createDirectory(at: imageset, withIntermediateDirectories: true)

            var images: [[String: String]] = []
            let lightName = "\(entry.kind.rawValue).svg"
            try fileManager.copyItem(at: source, to: imageset.appending(path: lightName))
            images.append(["filename": lightName, "idiom": "universal"])

            // An optional dark variant beside the source: "<stem>-dark.svg".
            let stem = (entry.sourceFileName as NSString).deletingPathExtension
            let darkSource = sourceDirectory.appending(path: "\(stem)-dark.svg")
            if fileManager.fileExists(atPath: darkSource.path) {
                let darkName = "\(entry.kind.rawValue)-dark.svg"
                try fileManager.copyItem(at: darkSource, to: imageset.appending(path: darkName))
                images.append([
                    "filename": darkName,
                    "idiom": "universal",
                    "appearances": "dark"
                ])
                mapped.insert("\(stem)-dark.svg")
            }

            try writeContents(images: images, to: imageset.appending(path: "Contents.json"))
            print("synced \(name) ← \(entry.sourceFileName)\(images.count > 1 ? " (+dark)" : "")")
        }

        let present = (try? fileManager.contentsOfDirectory(atPath: sourceDirectory.path)) ?? []
        let unmapped = present.filter { $0.lowercased().hasSuffix(".svg") && !mapped.contains($0) }.sorted()
        for file in unmapped {
            print("note: \(file) matches no charm and was not synced")
        }
        for item in missing {
            FileHandle.standardError.write(Data("missing: \(item)\n".utf8))
        }
        print("synced \(CollectionCharmCatalog.entries.count - missing.count) of \(CollectionCharmCatalog.entries.count) charms")
        if !missing.isEmpty { exit(1) }
    }

    /// Imageset JSON with vector data preserved and a dark appearance when given.
    static func writeContents(images: [[String: String]], to url: URL) throws {
        let entries: [[String: Any]] = images.map { image in
            var entry: [String: Any] = ["filename": image["filename"] ?? "", "idiom": image["idiom"] ?? "universal"]
            if image["appearances"] == "dark" {
                entry["appearances"] = [["appearance": "luminosity", "value": "dark"]]
            }
            return entry
        }
        try writeJSON([
            "images": entries,
            "info": ["author": "xcode", "version": 1],
            "properties": ["preserves-vector-representation": true, "template-rendering-intent": "original"]
        ], to: url)
    }

    static func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
