//
//  CharmArtworkSplitter.swift
//  Hangly
//
//  Separates a charm's body from the beads threaded above it.
//

import CoreGraphics
import Foundation

/// A charm's artwork divided into the parts that hang independently.
///
/// Coordinates are in the artwork's fitted unit square, `(0, 0)` at the top left,
/// matching `VectorImage.raster(region:…)`.
struct CharmArtworkRegions: Sendable, Equatable {
    /// The charm itself, including whatever loop or hook it hangs by.
    var body: CGRect

    /// The beads above the body, ordered from the top down.
    var beads: [CGRect]

    /// Where the cord meets the body, as a fraction of the charm's radius measured
    /// back along the final link. The body is fitted into a square of side twice
    /// the radius, so this is the body's height over its longest side.
    var knotInset: Double {
        let longest = max(body.width, body.height)
        guard longest > 0 else { return 1 }
        return body.height / longest
    }

    /// Points per unit of this coordinate space, for a charm of the given radius.
    func scale(forRadius radius: Double) -> Double {
        let longest = max(body.width, body.height)
        guard longest > 0 else { return 0 }
        return (radius * 2) / longest
    }
}

/// Finds the beads in a piece of charm artwork, by looking at its silhouette.
///
/// Every charm in the collection is drawn as one tall picture: a cord at the top,
/// a few beads threaded onto it, then the charm. Rope beads need the beads and the
/// charm as separate sprites, and the artwork must not be edited to get them — so
/// the split is measured from the rendering instead.
///
/// The measurement is a row profile. A row crossed only by the cord is a few
/// percent of the artwork's width; a row through a bead or the charm is far wider.
/// Runs of wide rows are therefore the solid parts, separated by cord. Which of
/// those runs are beads, and which one begins the charm, is the one judgement a
/// picture cannot make — a thick cord and a fat bead look alike from here — so the
/// catalogue states both per charm. Runs above the body that are not beads are
/// cord furniture and are dropped, because the simulated thread replaces them.
enum CharmArtworkSplitter {
    /// Analysis resolution. Large enough to separate a bead from the cord, small
    /// enough that the rasterisation is a few milliseconds.
    static let analysisPixels = 320

    /// A row no wider than this fraction of the artwork is cord, not substance.
    /// The cords measure 5–7%; the narrowest bead is near 10%.
    static let cordWidthFraction = 0.085

    /// Rows thinner than this fraction of a run's widest row are trimmed from it,
    /// so a bead's bounds hug the bead instead of the cord entering it.
    static let edgeWidthFraction = 0.25

    /// Alpha at or below this counts as transparent.
    static let alphaThreshold: UInt8 = 8

    /// - Parameters:
    ///   - beadCount: How many of the runs, from the top, are beads.
    ///   - bodyRun: Index of the run where the charm itself begins. Defaults to
    ///     `beadCount`; a charm whose cord is thick enough to register as a run of
    ///     its own passes a larger index so that cord is dropped rather than drawn.
    /// - Returns: The split, or `nil` if the artwork does not have the parts the
    ///   catalogue expects — which the caller reports rather than papering over.
    static func split(_ vector: VectorImage, beadCount: Int, bodyRun: Int? = nil) -> CharmArtworkRegions? {
        let bodyIndex = bodyRun ?? beadCount
        guard beadCount >= 0, bodyIndex >= beadCount,
              let content = vector.unitContentRect,
              let image = vector.raster(pixelSide: analysisPixels, dark: false),
              let bitmap = RGBABitmap(image: image) else { return nil }

        let side = Double(analysisPixels)
        let rows = rowProfile(bitmap)
        let cordWidth = cordWidthFraction * content.width * side
        let runs = solidRuns(rows, minimumWidth: cordWidth)
        guard runs.count > bodyIndex else { return nil }

        let beads = runs.prefix(beadCount).map { unitRect(trim($0, in: rows), side: side) }

        // The body runs from the top of its own solid part to the last ink in the
        // artwork, so a hook or a tassel that thins out stays part of the charm.
        let bodyTop = runs[bodyIndex].first
        guard let bodyBottom = rows.lastIndex(where: { $0.width > 0 }), bodyBottom >= bodyTop else { return nil }
        var minX = Int.max
        var maxX = -1
        for row in bodyTop...bodyBottom where rows[row].width > 0 {
            minX = min(minX, rows[row].minX)
            maxX = max(maxX, rows[row].maxX)
        }
        guard maxX >= minX else { return nil }

        let body = unitRect(
            Run(first: bodyTop, last: bodyBottom, minX: minX, maxX: maxX),
            side: side
        )
        return CharmArtworkRegions(body: body, beads: beads)
    }

    // MARK: - Row profile

    private struct RowExtent {
        var minX = 0
        var maxX = 0
        var width = 0
    }

    private struct Run {
        var first: Int
        var last: Int
        var minX: Int
        var maxX: Int
    }

    /// Horizontal ink extent of every row, top-down.
    ///
    /// `RGBABitmap` built from a `CGImage` keeps the image's own row order, so row
    /// zero is the top of the artwork. A test asserts it, because the split is
    /// upside down if that ever changes.
    private static func rowProfile(_ bitmap: RGBABitmap) -> [RowExtent] {
        (0..<bitmap.height).map { y in
            var extent = RowExtent()
            var first = -1
            var last = -1
            for x in 0..<bitmap.width where bitmap.alpha(x: x, y: y) > alphaThreshold {
                if first < 0 { first = x }
                last = x
            }
            guard first >= 0 else { return extent }
            extent.minX = first
            extent.maxX = last
            extent.width = last - first + 1
            return extent
        }
    }

    /// Runs of consecutive rows wider than the cord.
    private static func solidRuns(_ rows: [RowExtent], minimumWidth: Double) -> [Run] {
        var runs: [Run] = []
        var current: Run?

        for (index, row) in rows.enumerated() {
            if Double(row.width) > minimumWidth {
                if var run = current {
                    run.last = index
                    run.minX = min(run.minX, row.minX)
                    run.maxX = max(run.maxX, row.maxX)
                    current = run
                } else {
                    current = Run(first: index, last: index, minX: row.minX, maxX: row.maxX)
                }
            } else if let run = current {
                runs.append(run)
                current = nil
            }
        }
        if let run = current { runs.append(run) }
        return runs
    }

    /// Drops the rows at a run's ends where only the cord remains, and re-measures
    /// the horizontal bounds over what is left.
    private static func trim(_ run: Run, in rows: [RowExtent]) -> Run {
        let widest = (run.first...run.last).map { rows[$0].width }.max() ?? 0
        let floor = Double(widest) * edgeWidthFraction
        var first = run.first
        var last = run.last
        while first < last, Double(rows[first].width) < floor { first += 1 }
        while last > first, Double(rows[last].width) < floor { last -= 1 }

        var minX = Int.max
        var maxX = -1
        for row in first...last where rows[row].width > 0 {
            minX = min(minX, rows[row].minX)
            maxX = max(maxX, rows[row].maxX)
        }
        guard maxX >= minX else { return run }
        return Run(first: first, last: last, minX: minX, maxX: maxX)
    }

    private static func unitRect(_ run: Run, side: Double) -> CGRect {
        CGRect(
            x: Double(run.minX) / side,
            y: Double(run.first) / side,
            width: Double(run.maxX - run.minX + 1) / side,
            height: Double(run.last - run.first + 1) / side
        )
    }
}
