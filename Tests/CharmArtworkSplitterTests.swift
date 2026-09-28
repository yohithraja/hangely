//
//  CharmArtworkSplitterTests.swift
//  HanglyTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Hangly

/// The artwork is one picture; the overlay needs it as a charm plus its beads.
///
/// The split is measured from the rendering rather than written down, so these tests
/// are what stands between a re-exported asset and a charm that hangs upside down or
/// loses its loop.
@Suite("Charm artwork split")
struct CharmArtworkSplitterTests {
    private let bundled = SVGArtworkSource(backend: .bundle)

    @Test("Every collection charm splits into the parts the catalogue declares")
    func everyCharmSplits() throws {
        for entry in CollectionCharmCatalog.entries {
            let vector = try #require(bundled.vectorImage(for: entry.kind), "\(entry.kind) has no asset")
            let regions = try #require(
                vector.regions(beadCount: entry.beadCount, bodyRun: entry.bodyRun),
                "\(entry.kind) could not be split"
            )

            #expect(regions.beads.count == entry.beadCount, "\(entry.kind) bead count")
            #expect(regions.body.width > 0)
            #expect(regions.body.height > 0)

            let square = CGRect(x: 0, y: 0, width: 1, height: 1)
            #expect(square.contains(regions.body), "\(entry.kind) body escapes the artwork")
            for bead in regions.beads {
                #expect(square.contains(bead), "\(entry.kind) bead escapes the artwork")
            }
        }
    }

    @Test("Beads are above the charm and in order, which is also the test that the artwork is not upside down")
    func beadsAreAboveTheBody() throws {
        for entry in CollectionCharmCatalog.entries where entry.beadCount > 0 {
            let vector = try #require(bundled.vectorImage(for: entry.kind))
            let regions = try #require(vector.regions(beadCount: entry.beadCount, bodyRun: entry.bodyRun))

            var lowest = 0.0
            for bead in regions.beads {
                #expect(bead.minY >= lowest, "\(entry.kind) beads out of order")
                lowest = bead.maxY
            }
            #expect(lowest <= regions.body.minY, "\(entry.kind) beads overlap the charm")
        }
    }

    @Test("Every region holds artwork rather than empty space")
    func regionsContainInk() throws {
        for entry in CollectionCharmCatalog.entries {
            let vector = try #require(bundled.vectorImage(for: entry.kind))
            let regions = try #require(vector.regions(beadCount: entry.beadCount, bodyRun: entry.bodyRun))

            for (index, region) in ([regions.body] + regions.beads).enumerated() {
                let width = max(16, Int(region.width * 240))
                let height = max(16, Int(region.height * 240))
                let image = try #require(
                    vector.raster(region: region, pixelWidth: width, pixelHeight: height, dark: false)
                )
                let bitmap = try #require(RGBABitmap(image: image))
                #expect(bitmap.coverage(threshold: 8) > 0.1, "\(entry.kind) region \(index) is nearly empty")
            }
        }
    }

    @Test("The charm is the whole picture below its beads, hook and all")
    func bodyReachesTheBottom() throws {
        for entry in CollectionCharmCatalog.entries {
            let vector = try #require(bundled.vectorImage(for: entry.kind))
            let regions = try #require(vector.regions(beadCount: entry.beadCount, bodyRun: entry.bodyRun))
            let content = try #require(vector.unitContentRect)

            #expect(regions.body.maxY > content.maxY - 0.02, "\(entry.kind) body is cut short")
            // Taller than wide, so the cord meets it at the top of its square.
            #expect(regions.knotInset == 1)
        }
    }

    @Test("A split is measured once and kept")
    func splitsAreCached() throws {
        let vector = try #require(bundled.vectorImage(for: .daruma))
        vector.purge()
        let first = try #require(vector.regions(beadCount: 3, bodyRun: 3))
        let second = try #require(vector.regions(beadCount: 3, bodyRun: 3))
        #expect(first == second)

        // A different reading of the same artwork is measured separately.
        let other = try #require(vector.regions(beadCount: 1, bodyRun: 1))
        #expect(other.beads.count == 1)
        #expect(other.body.minY < first.body.minY)
    }

    @Test("Asking for parts the artwork does not have fails rather than inventing them")
    func impossibleSplitsAreRejected() throws {
        let vector = try #require(bundled.vectorImage(for: .himmeli))
        #expect(vector.regions(beadCount: 40, bodyRun: 40) == nil)
        #expect(CharmArtworkSplitter.split(vector, beadCount: -1) == nil)
    }
}
