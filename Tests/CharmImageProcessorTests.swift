//
//  CharmImageProcessorTests.swift
//  HanglyTests
//

import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Hangly

/// The pipeline is a chain of pure functions over pixels, so each link is checked
/// on synthetic images whose correct answer is known exactly.
@Suite("Charm image processing")
struct CharmImageProcessorTests {
    private func fixtureFile(_ image: CGImage, as type: UTType, name: String) throws -> URL {
        let directory = try TestImages.temporaryDirectory()
        let url = directory.appending(path: name)
        try TestImages.write(image, as: type, to: url)
        return url
    }

    // MARK: - Loading

    @Test("PNG and JPEG files load")
    func loadsPNGAndJPEG() throws {
        let disc = try #require(TestImages.discOnWhite())

        let png = try CharmImageProcessor.load(fileAt: fixtureFile(disc, as: .png, name: "disc.png"))
        let jpeg = try CharmImageProcessor.load(fileAt: fixtureFile(disc, as: .jpeg, name: "disc.jpg"))

        #expect(png.width == 256)
        #expect(jpeg.width == 256)
    }

    @Test("WebP files load")
    func loadsWebP() throws {
        let directory = try TestImages.temporaryDirectory()
        let url = directory.appending(path: "pixel.webp")
        try TestImages.webpLossless1x1.write(to: url)

        let image = try CharmImageProcessor.load(fileAt: url)
        #expect(image.width == 1)
        #expect(image.height == 1)
    }

    @Test("Other image formats are refused by name")
    func refusesUnsupportedFormats() throws {
        let disc = try #require(TestImages.discOnWhite())
        let gif = try fixtureFile(disc, as: .gif, name: "disc.gif")

        #expect(throws: CharmImageError.unsupportedType("disc.gif")) {
            try CharmImageProcessor.load(fileAt: gif)
        }
        #expect(CharmImageProcessor.isSupported(gif) == false)
        #expect(CharmImageProcessor.isSupported(URL(fileURLWithPath: "/tmp/a.PNG")))
        #expect(CharmImageProcessor.isSupported(URL(fileURLWithPath: "/tmp/a.webp")))
    }

    @Test("Oversized sources are downsampled on load")
    func downsamplesLargeSources() throws {
        let large = try #require(TestImages.discOnWhite(side: 3000))
        let url = try fixtureFile(large, as: .png, name: "large.png")

        let loaded = try CharmImageProcessor.load(fileAt: url)
        #expect(loaded.width <= CharmImageProcessor.maximumSourceSide)
    }

    // MARK: - Background removal

    @Test("Flood fill clears a flat background and keeps the subject")
    func floodFillRemovesBackground() throws {
        let disc = try #require(TestImages.discOnWhite())
        let result = try CharmImageProcessor.floodFillBackground(of: disc)
        let bitmap = try #require(RGBABitmap(image: result))

        #expect(bitmap.alpha(x: 2, y: 2) == 0)
        #expect(bitmap.alpha(x: 253, y: 253) == 0)
        #expect(bitmap.alpha(x: 128, y: 128) == 255)
        #expect(bitmap.coverage(threshold: 8) > 0.40)
        #expect(bitmap.coverage(threshold: 8) < 0.50)
    }

    @Test("An image that is already cut out is left alone")
    func trustsExistingAlpha() throws {
        let clear = try #require(TestImages.discOnClear())
        let opaque = try #require(TestImages.discOnWhite())

        #expect(CharmImageProcessor.hasMeaningfulAlpha(clear))
        #expect(CharmImageProcessor.hasMeaningfulAlpha(opaque) == false)

        let isolated = try CharmImageProcessor.isolateSubject(in: clear, strategy: .automatic)
        let bitmap = try #require(RGBABitmap(image: isolated))
        #expect(bitmap.alpha(x: 128, y: 128) == 255)
        #expect(bitmap.alpha(x: 2, y: 2) == 0)
    }

    // MARK: - Fitting and analysis

    @Test("Fitting yields a transparent square with the subject filling most of it")
    func fitsToSquare() throws {
        let cut = try #require(TestImages.discOnClear())
        let square = try CharmImageProcessor.fitToSquare(cut)
        let bitmap = try #require(RGBABitmap(image: square))
        let bounds = try #require(bitmap.opaqueBounds(threshold: 8))

        #expect(square.width == CharmImageProcessor.outputSide)
        #expect(square.height == CharmImageProcessor.outputSide)
        #expect(bitmap.alpha(x: 0, y: 0) == 0)

        let expectedSpan = Double(CharmImageProcessor.outputSide) * CharmImageProcessor.subjectFill
        #expect(abs(Double(bounds.width) - expectedSpan) < 4)
        #expect(abs(Double(bounds.height) - expectedSpan) < 4)
        // Centred.
        #expect(abs(Double(bounds.minX + bounds.maxX) / 2 - 255.5) < 2)
    }

    @Test("Nothing visible is an error, not an invisible charm")
    func rejectsEmptyImages() throws {
        let empty = try #require(TestImages.fullyTransparent())

        #expect(throws: CharmImageError.noVisibleContent) {
            try CharmImageProcessor.fitToSquare(empty)
        }
    }

    @Test("Analysis derives believable physics and a matching palette")
    func analysisIsSensible() throws {
        let cut = try #require(TestImages.discOnClear())
        let square = try CharmImageProcessor.fitToSquare(cut)
        let analysis = try CharmImageProcessor.analyze(square)

        #expect(analysis.metrics.mass >= 2.0)
        #expect(analysis.metrics.mass <= 4.5)
        #expect(analysis.metrics.radiusRatio > 0)
        // The disc's top sits at the fill margin, so the knot lands just inside it.
        #expect(abs(analysis.metrics.knotInset - CharmImageProcessor.subjectFill) < 0.03)
        // The cord should take the disc's red.
        #expect(analysis.palette.primary.red > 0.7)
        #expect(analysis.palette.primary.green < 0.4)
    }

    @Test("A solid shape is heavier than a sparse one")
    func massFollowsCoverage() throws {
        let solid = try #require(TestImages.makeImage(side: 128) { context in
            context.clear(CGRect(x: 0, y: 0, width: 128, height: 128))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 8, y: 8, width: 112, height: 112))
        })
        let sparse = try #require(TestImages.makeImage(side: 128) { context in
            context.clear(CGRect(x: 0, y: 0, width: 128, height: 128))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 60, y: 8, width: 8, height: 112))
        })

        let solidMass = try CharmImageProcessor.analyze(CharmImageProcessor.fitToSquare(solid)).metrics.mass
        let sparseMass = try CharmImageProcessor.analyze(CharmImageProcessor.fitToSquare(sparse)).metrics.mass

        #expect(solidMass > sparseMass + 0.5)
    }

    // MARK: - End to end

    @Test("A PNG on white becomes a transparent square charm bitmap")
    func processesPNGEndToEnd() async throws {
        let disc = try #require(TestImages.discOnWhite())
        let url = try fixtureFile(disc, as: .png, name: "disc.png")

        let processed = try await CharmImageProcessor.process(fileAt: url, backgroundRemoval: .floodFill)
        let decoded = try CharmImageProcessor.load(fileAt: {
            let out = url.deletingLastPathComponent().appending(path: "out.png")
            try processed.pngData.write(to: out)
            return out
        }())
        let bitmap = try #require(RGBABitmap(image: decoded))

        #expect(processed.pixelSide == CharmImageProcessor.outputSide)
        #expect(decoded.width == CharmImageProcessor.outputSide)
        #expect(bitmap.alpha(x: 0, y: 0) == 0)
        #expect(bitmap.alpha(x: 256, y: 256) == 255)
    }

    @Test("A JPEG with no alpha channel comes out with its background removed")
    func processesJPEGAutomatically() async throws {
        let disc = try #require(TestImages.discOnWhite())
        let url = try fixtureFile(disc, as: .jpeg, name: "disc.jpg")

        // Automatic mode: Vision if it sees a subject, flood fill if not. Either
        // must leave the corners clear and the centre solid.
        let processed = try await CharmImageProcessor.process(fileAt: url, backgroundRemoval: .automatic)
        let out = url.deletingLastPathComponent().appending(path: "out.png")
        try processed.pngData.write(to: out)
        let bitmap = try #require(RGBABitmap(image: try CharmImageProcessor.load(fileAt: out)))

        #expect(bitmap.alpha(x: 0, y: 0) == 0)
        #expect(bitmap.alpha(x: 256, y: 256) > 200)
    }
}
