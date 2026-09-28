//
//  GenerateCharmPreviews.swift
//  Hangly
//
//  Renders every built-in charm to a preview PNG in the asset catalog, and
//  optionally a contact sheet of the whole collection. Run via
//  Scripts/generate-charm-previews.sh, which compiles this with the charm sources.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct GenerateCharmPreviews {
    static let previewPoints = 256.0

    static func main() throws {
        let arguments = CommandLine.arguments.dropFirst()
        guard let catalogPath = arguments.first else {
            FileHandle.standardError.write(Data("usage: previews <CharmPreviews folder> [sheet.png]\n".utf8))
            exit(2)
        }
        let catalog = URL(fileURLWithPath: catalogPath)
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        try writeJSON(["info": ["author": "xcode", "version": 1]], to: catalog.appending(path: "Contents.json"))

        for charm in BuiltInCharms.all {
            try MainActor.assumeIsolated { try writePreview(for: charm, into: catalog) }
        }
        print("Wrote \(BuiltInCharms.all.count) previews to \(catalog.path)")

        if let sheetPath = arguments.dropFirst().first {
            try MainActor.assumeIsolated { try writeSheet(to: URL(fileURLWithPath: sheetPath)) }
            print("Wrote collection sheet to \(sheetPath)")
        }
    }

    @MainActor
    static func writePreview(for charm: any Charm, into catalog: URL) throws {
        guard case .builtIn(let kind) = charm.id else { return }
        let name = "charm-preview-\(kind.rawValue)"
        let folder = catalog.appending(path: "\(name).imageset")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let view = CharmView(charm: charm, inset: 0.82)
            .frame(width: previewPoints, height: previewPoints)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }

        try writePNG(image, to: folder.appending(path: "\(name)@2x.png"))
        try writeJSON([
            "images": [["filename": "\(name)@2x.png", "idiom": "universal", "scale": "2x"]],
            "info": ["author": "xcode", "version": 1]
        ], to: folder.appending(path: "Contents.json"))
    }

    /// A first-party contact sheet of the collection: six per row, named.
    @MainActor
    static func writeSheet(to url: URL) throws {
        let charms = BuiltInCharms.all
        let columns = 6
        let rows = Int((Double(charms.count) / Double(columns)).rounded(.up))
        let cell = 170.0
        let sheet = VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < charms.count {
                            VStack(spacing: 10) {
                                CharmView(charm: charms[index], inset: 0.8)
                                    .frame(width: 118, height: 118)
                                Text(charms[index].displayName)
                                    .font(.system(size: 14, weight: .semibold, design: .serif))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: cell)
                        } else {
                            Color.clear.frame(width: cell, height: 1)
                        }
                    }
                }
            }
            Text("Hangly")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 18)
            Text("BRING YOUR DESKTOP TO LIFE")
                .font(.system(size: 12, weight: .medium))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(40)
        .background(Color(red: 0.07, green: 0.08, blue: 0.11))

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        try writePNG(image, to: url)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
