//
//  TestImages.swift
//  HanglyTests
//
//  Synthetic image fixtures, generated rather than checked in.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImages {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    static func makeImage(side: Int, draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(context)
        return context.makeImage()
    }

    /// A red disc on an opaque white ground: the "clip art on white" case.
    static func discOnWhite(side: Int = 256) -> CGImage? {
        makeImage(side: side) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            drawDisc(in: context, side: side)
        }
    }

    /// The same disc on a transparent ground: the "already cut out" case.
    static func discOnClear(side: Int = 256) -> CGImage? {
        makeImage(side: side) { context in
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            drawDisc(in: context, side: side)
        }
    }

    /// Nothing visible at all.
    static func fullyTransparent(side: Int = 64) -> CGImage? {
        makeImage(side: side) { context in
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private static func drawDisc(in context: CGContext, side: Int) {
        let radius = Double(side) * 0.38
        let centre = Double(side) / 2
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.15, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(
            x: centre - radius,
            y: centre - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    static func write(_ image: CGImage, as type: UTType, to url: URL) throws {
        let identifier = type.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, identifier, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "HanglyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A one-pixel lossless WebP. ImageIO decodes WebP but cannot encode it, so a
    /// known-good file is embedded rather than generated.
    static var webpLossless1x1: Data {
        Data(base64Encoded: "UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==") ?? Data()
    }
}
