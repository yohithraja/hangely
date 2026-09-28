//
//  GenerateAppIcon.swift
//  Hangly
//
//  Slices the master icon artwork into a complete macOS AppIcon set.
//  Run via Scripts/generate-app-icon.sh.
//

import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

@main
struct GenerateAppIcon {
    /// Every slot macOS asks for, as (points, scale).
    static let slots: [(points: Int, scale: Int)] = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2)
    ]

    /// Apple's grid for a rounded-rectangle macOS icon: the shape spans 824 of the
    /// 1024-point canvas, leaving 100 points of air on each side. An icon that
    /// ignores this sits visibly larger or smaller than its neighbours in the Dock,
    /// which is the difference between looking native and looking imported.
    static let shapeSpan = 824.0
    static let canvasSpan = 1024.0

    /// Alpha at or below this is treated as empty when measuring the artwork.
    static let alphaThreshold: UInt8 = 12

    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("usage: appicon <master.png> <AppIcon.appiconset dir>\n".utf8))
            exit(2)
        }
        let masterURL = URL(fileURLWithPath: arguments[0])
        let output = URL(fileURLWithPath: arguments[1])

        guard let master = loadMaster(masterURL) else {
            FileHandle.standardError.write(Data("error: could not read \(masterURL.path)\n".utf8))
            exit(1)
        }
        guard let bounds = opaqueBounds(master) else {
            FileHandle.standardError.write(Data("error: the master is entirely transparent\n".utf8))
            exit(1)
        }

        print("master  \(master.width)×\(master.height)")
        print("artwork \(Int(bounds.width))×\(Int(bounds.height)) at (\(Int(bounds.minX)), \(Int(bounds.minY)))")
        let fill = bounds.width / Double(master.width)
        print(String(format: "        fills %.1f%% of the canvas; Apple's grid wants %.1f%%",
                     fill * 100, shapeSpan / canvasSpan * 100))

        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var written: [[String: String]] = []

        for slot in slots {
            let pixels = slot.points * slot.scale
            let name = "icon_\(slot.points)x\(slot.points)\(slot.scale == 2 ? "@2x" : "").png"
            // Every size is resampled from the master, never from a smaller
            // intermediate: one high-quality downsample is always sharper than two.
            let image = try render(master, artwork: bounds, pixels: pixels)
            try write(image, to: output.appending(path: name))
            written.append([
                "filename": name,
                "idiom": "mac",
                "scale": "\(slot.scale)x",
                "size": "\(slot.points)x\(slot.points)"
            ])
            print("  \(pixels)×\(pixels)  \(name)")
        }

        try writeJSON(["images": written, "info": ["author": "xcode", "version": 1]],
                      to: output.appending(path: "Contents.json"))
        print("Wrote \(written.count) images to \(output.path)")
    }

    // MARK: - Loading

    /// Reads the master and converts it to sRGB, so every slice carries one known
    /// colour space rather than whatever the artwork arrived tagged as.
    static func loadMaster(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let converted = context.makeImage() else { return nil }
        return normalisingAlpha(converted)
    }

    /// Alpha at or above this is artwork that means to be solid.
    static let nearlyOpaque: UInt8 = 250

    /// Lifts the body of the artwork to fully opaque.
    ///
    /// Artwork can arrive a percent or two short of opaque across its whole face —
    /// invisible on its own, but it means the desktop shows faintly through an icon
    /// that should be solid. Only pixels already at `nearlyOpaque` are lifted, so
    /// every soft edge and cast shadow keeps exactly the falloff it was drawn with.
    /// Colour is unpremultiplied before the change and premultiplied after, so no
    /// highlight clips on the way through.
    static func normalisingAlpha(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let read = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard read else { return image }

        var lifted = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[index + 3]
            guard alpha >= nearlyOpaque, alpha < 255 else { continue }
            let scale = 255.0 / Double(alpha)
            for channel in 0..<3 {
                pixels[index + channel] = UInt8(min(255, (Double(pixels[index + channel]) * scale).rounded()))
            }
            pixels[index + 3] = 255
            lifted += 1
        }
        guard lifted > 0 else { return image }
        print("        lifted \(lifted) pixels to fully opaque")

        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return image }
            return context.makeImage()
        } ?? image
    }

    /// The artwork's own bounds inside the master's canvas, ignoring transparent margin.
    static func opaqueBounds(_ image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[((y * width) + x) * 4 + 3] > alphaThreshold {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - Rendering

    /// Draws the artwork onto a square canvas at Apple's proportions.
    static func render(_ master: CGImage, artwork: CGRect, pixels: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }

        context.interpolationQuality = .high
        context.setShouldAntialias(true)

        // Scale so the artwork's longest side lands on the grid's span, then centre
        // it. The master is drawn in full — the maths only moves and scales it, so
        // nothing is cropped and no edge is resampled twice.
        let target = Double(pixels) * (shapeSpan / canvasSpan)
        let longest = max(artwork.width, artwork.height)
        let scale = target / longest

        let drawWidth = Double(master.width) * scale
        let drawHeight = Double(master.height) * scale
        // CoreGraphics is y-up; the measured bounds are y-down.
        let originX = (Double(pixels) - (artwork.width * scale)) / 2 - (artwork.minX * scale)
        let flippedMinY = Double(master.height) - artwork.maxY
        let originY = (Double(pixels) - (artwork.height * scale)) / 2 - (flippedMinY * scale)

        context.draw(master, in: CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight))
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
