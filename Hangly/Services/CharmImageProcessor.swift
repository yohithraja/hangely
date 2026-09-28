//
//  CharmImageProcessor.swift
//  Hangly
//
//  Turns a dropped image file into a charm-ready bitmap.
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// The output of the pipeline: everything the store needs, and nothing else.
struct ProcessedCharmImage: Sendable {
    let pngData: Data
    let pixelSide: Int
    let metrics: CharmMetrics
    let palette: CharmPalette
}

enum CharmImageError: LocalizedError, Equatable {
    case unsupportedType(String)
    case unreadable
    case noVisibleContent
    case noSubjectDetected
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let name):
            "“\(name)” is not a supported image. Choose a PNG, JPEG, WebP or HEIC file."
        case .unreadable:
            "The image could not be read."
        case .noVisibleContent:
            "Nothing was left after removing the background. Try an image with a clearer subject."
        case .noSubjectDetected:
            "No subject was detected in this image. Try Flat background or Keep original."
        case .encodingFailed:
            "The charm image could not be saved."
        }
    }
}

/// Image file → charm bitmap, plus the numbers the rope needs.
///
/// The pipeline is a straight line of pure functions, each testable alone:
///
/// ```
/// load  →  isolate subject  →  fit to square  →  analyse  →  encode PNG
/// ```
///
/// Subject isolation tries three things in order. If the file already carries
/// meaningful transparency it is trusted as-is, because a sticker that has been
/// cut out by hand should not be cut again. Otherwise Vision's subject lifting is
/// asked for the foreground, which handles photographs. If it finds nothing, a
/// corner flood fill removes a flat background, which handles clip art and product
/// shots on white.
///
/// Everything runs off the main actor. The inputs and outputs are all `Sendable`.
enum CharmImageProcessor {
    enum BackgroundRemoval: Sendable {
        /// Existing alpha, then Vision, then flood fill.
        case automatic
        /// Flood fill only. Deterministic, used by tests.
        case floodFill
        /// Keep the image as it is.
        case none
    }

    static let supportedTypes: [UTType] = [.png, .jpeg, .webP, .heic, .heif]

    /// Side of the square bitmap written to disk. Plenty for a charm that is drawn
    /// at a few dozen points even on a 2x display at double scale.
    static let outputSide = 512

    /// Sources are downsampled to this before any work, so a 50-megapixel photo
    /// costs the same as a screenshot.
    static let maximumSourceSide = 2048

    /// Fraction of the square the subject spans, leaving a margin for the shadow.
    static let subjectFill = 0.92

    static let opaqueThreshold: UInt8 = 8
    static let floodFillTolerance = 36

    /// Below this share of transparent pixels, alpha is treated as incidental.
    static let meaningfulAlphaFraction = 0.02

    static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Pipeline

    static func process(
        fileAt url: URL,
        backgroundRemoval: BackgroundRemoval = .automatic
    ) async throws -> ProcessedCharmImage {
        try await Task.detached(priority: .userInitiated) {
            let source = try load(fileAt: url)
            let isolated = try isolateSubject(in: source, strategy: backgroundRemoval)
            let square = try fitToSquare(isolated)
            let analysis = try analyze(square)
            let png = try encodePNG(square)
            return ProcessedCharmImage(
                pngData: png,
                pixelSide: outputSide,
                metrics: analysis.metrics,
                palette: analysis.palette
            )
        }.value
    }

    /// Decodes and downsamples. Rejects anything that is not PNG, JPEG or WebP.
    static func load(fileAt url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CharmImageError.unreadable
        }

        // Bytes ImageIO cannot identify at all are an unreadable file, whatever the
        // extension claims. Only a recognised format outside the list is "unsupported".
        guard let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier) else {
            throw CharmImageError.unreadable
        }
        guard supportedTypes.contains(where: { type.conforms(to: $0) }) else {
            throw CharmImageError.unsupportedType(url.lastPathComponent)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSourceSide,
            kCGImageSourceShouldCache: false
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CharmImageError.unreadable
        }
        return image
    }

    static func isolateSubject(in image: CGImage, strategy: BackgroundRemoval) throws -> CGImage {
        switch strategy {
        case .none:
            return image
        case .floodFill:
            return try floodFillBackground(of: image)
        case .automatic:
            if hasMeaningfulAlpha(image) {
                return image
            }
            // Vision failing is not fatal; the flood fill is the answer either way.
            if let lifted = try? liftSubject(from: image) {
                return lifted
            }
            return try floodFillBackground(of: image)
        }
    }

    static func hasMeaningfulAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            guard let bitmap = RGBABitmap(image: image) else { return false }
            return bitmap.transparentFraction(threshold: opaqueThreshold) > meaningfulAlphaFraction
        }
    }

    /// Vision's foreground lifting. `nil` when it sees no subject.
    static func liftSubject(from image: CGImage) throws -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            return nil
        }

        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )
        let ciImage = CIImage(cvPixelBuffer: buffer)
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(ciImage, from: ciImage.extent)
    }

    static func floodFillBackground(of image: CGImage, tolerance: Int = floodFillTolerance) throws -> CGImage {
        guard var bitmap = RGBABitmap(image: image) else { throw CharmImageError.unreadable }
        bitmap.floodFillBackground(tolerance: tolerance)
        bitmap.featherAlphaEdges()
        guard let result = bitmap.makeImage() else { throw CharmImageError.encodingFailed }
        return result
    }

    /// Crops to the visible pixels and scales them into a transparent square with a
    /// margin, so every charm bitmap maps to the unit square the same way.
    static func fitToSquare(_ image: CGImage, fill: Double = subjectFill) throws -> CGImage {
        guard let bitmap = RGBABitmap(image: image) else { throw CharmImageError.unreadable }
        guard let bounds = bitmap.opaqueBounds(threshold: opaqueThreshold) else {
            throw CharmImageError.noVisibleContent
        }

        let scale = (Double(outputSide) * fill.clamped(to: 0.3...1)) / Double(max(bounds.width, bounds.height))
        let targetWidth = max(1, (Double(bounds.width) * scale).rounded())
        let targetHeight = max(1, (Double(bounds.height) * scale).rounded())
        let target = CGRect(
            x: (Double(outputSide) - targetWidth) / 2,
            y: (Double(outputSide) - targetHeight) / 2,
            width: targetWidth,
            height: targetHeight
        )

        guard let context = RGBABitmap.makeContext(data: nil, width: outputSide, height: outputSide) else {
            throw CharmImageError.encodingFailed
        }
        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))

        // Draw the whole image scaled and offset so the crop region lands exactly on
        // `target`, clipped to it. Bounds are bottom-up, matching CG's draw space, so
        // no orientation flip is needed here.
        context.clip(to: target)
        context.draw(image, in: CGRect(
            x: target.minX - (Double(bounds.minX) * scale),
            y: target.minY - (Double(bounds.minY) * scale),
            width: Double(image.width) * scale,
            height: Double(image.height) * scale
        ))

        guard let result = context.makeImage() else { throw CharmImageError.encodingFailed }
        return result
    }

    /// Derives the rope-facing numbers from the final square.
    ///
    /// Mass follows coverage: a solid shape that fills its square is heavier than a
    /// wispy one, which is both intuitive and what keeps very different imports
    /// swinging believably. The knot inset follows the top-most visible row, so the
    /// cord's loop sits on the image's actual top edge.
    static func analyze(_ square: CGImage) throws -> (metrics: CharmMetrics, palette: CharmPalette) {
        guard let bitmap = RGBABitmap(image: square) else { throw CharmImageError.unreadable }
        guard let bounds = bitmap.opaqueBounds(threshold: opaqueThreshold) else {
            throw CharmImageError.noVisibleContent
        }

        let coverage = bitmap.coverage(threshold: opaqueThreshold)
        let mass = (2.0 + (3.2 * coverage)).clamped(to: 2.0...4.5)

        // Rows are bottom-up, so the top edge is `maxY`. Convert to a distance from
        // the centre as a fraction of the half-side.
        let topFromTop = 1 - (Double(bounds.maxY + 1) / Double(bitmap.height))
        let knotInset = ((0.5 - topFromTop) / 0.5).clamped(to: 0.3...1.0)

        let base = bitmap.averageColor(threshold: opaqueThreshold) ?? CharmColor(0.6, 0.6, 0.65)
        return (
            CharmMetrics(mass: mass, radiusRatio: 0.12, knotInset: knotInset),
            .derived(from: base)
        )
    }

    static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CharmImageError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CharmImageError.encodingFailed }
        return data as Data
    }
}
