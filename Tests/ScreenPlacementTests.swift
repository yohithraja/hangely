//
//  ScreenPlacementTests.swift
//  HanglyTests
//

import CoreGraphics
import Testing

@testable import Hangly

/// `ScreenPlacement` is pure geometry, so the anchoring rules can be verified
/// exactly — no display, no window server, no timing.
@Suite("Screen placement")
struct ScreenPlacementTests {
    /// A 1600x1000 display whose origin is the global origin.
    private let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private let size = CGSize(width: 180, height: 260)
    private let inset: CGFloat = 12

    @Test("Top-center sits on the horizontal midpoint of the screen")
    func topCenterIsHorizontallyCentred() {
        let frame = ScreenPlacement.frame(for: size, anchor: .topCenter, in: bounds, edgeInset: inset)

        #expect(frame.midX == bounds.midX)
        #expect(frame.size == size)
    }

    @Test("Top anchors hang from the top edge, inset by the margin")
    func topAnchorsHangFromTheTop() {
        for anchor in OverlayAnchor.allCases {
            let frame = ScreenPlacement.frame(for: size, anchor: anchor, in: bounds, edgeInset: inset)

            // AppKit coordinates are y-up, so the top edge is maxY.
            #expect(frame.maxY == bounds.maxY - inset)
        }
    }

    @Test("Leading and trailing anchors respect the edge inset")
    func horizontalAnchorsRespectInset() {
        let leading = ScreenPlacement.frame(for: size, anchor: .topLeading, in: bounds, edgeInset: inset)
        let trailing = ScreenPlacement.frame(for: size, anchor: .topTrailing, in: bounds, edgeInset: inset)

        #expect(leading.minX == bounds.minX + inset)
        #expect(trailing.maxX == bounds.maxX - inset)
    }

    @Test("A positive vertical offset moves the overlay down the screen")
    func positiveVerticalOffsetMovesDown() {
        let base = ScreenPlacement.frame(for: size, anchor: .topCenter, in: bounds, edgeInset: inset)
        let shifted = ScreenPlacement.frame(
            for: size,
            anchor: .topCenter,
            in: bounds,
            offset: CGPoint(x: 0, y: 30),
            edgeInset: inset
        )

        // Down the screen means a *lower* maxY in AppKit's y-up space.
        #expect(shifted.maxY == base.maxY - 30)
        #expect(shifted.minX == base.minX)
    }

    @Test("A positive horizontal offset moves the overlay right")
    func positiveHorizontalOffsetMovesRight() {
        let base = ScreenPlacement.frame(for: size, anchor: .topCenter, in: bounds, edgeInset: inset)
        let shifted = ScreenPlacement.frame(
            for: size,
            anchor: .topCenter,
            in: bounds,
            offset: CGPoint(x: 50, y: 0),
            edgeInset: inset
        )

        #expect(shifted.minX == base.minX + 50)
    }

    @Test("An extreme offset is clamped so the overlay stays on screen")
    func extremeOffsetsAreClamped() {
        let farRight = ScreenPlacement.frame(
            for: size,
            anchor: .topCenter,
            in: bounds,
            offset: CGPoint(x: 100_000, y: 0),
            edgeInset: inset
        )
        let farLeft = ScreenPlacement.frame(
            for: size,
            anchor: .topCenter,
            in: bounds,
            offset: CGPoint(x: -100_000, y: 0),
            edgeInset: inset
        )
        let farDown = ScreenPlacement.frame(
            for: size,
            anchor: .topCenter,
            in: bounds,
            offset: CGPoint(x: 0, y: 100_000),
            edgeInset: inset
        )

        #expect(farRight.maxX == bounds.maxX)
        #expect(farLeft.minX == bounds.minX)
        #expect(farDown.minY == bounds.minY)
    }

    @Test("Placement works on a display left of the global origin")
    func handlesNegativeScreenOrigin() {
        // A second display positioned to the left of the primary has a negative
        // origin in global screen coordinates.
        let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = ScreenPlacement.frame(for: size, anchor: .topCenter, in: secondary, edgeInset: inset)

        #expect(frame.midX == secondary.midX)
        #expect(frame.maxY == secondary.maxY - inset)
        #expect(frame.minX < 0)
    }

    @Test("An overlay larger than the screen is left alone rather than mangled")
    func oversizedRectIsNotClamped() {
        let huge = CGSize(width: 2000, height: 3000)
        let frame = ScreenPlacement.frame(for: huge, anchor: .topCenter, in: bounds)

        #expect(frame.size == huge)
    }
}
