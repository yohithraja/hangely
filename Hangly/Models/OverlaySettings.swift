//
//  OverlaySettings.swift
//  Hangly
//
//  Value type describing how the floating overlay should be presented.
//

import Foundation

/// Everything the overlay window controller needs in order to present the overlay.
///
/// This is a pure value type: no AppKit, no observation, no persistence. It is the
/// single source of truth that flows from `SettingsStore` down to the window layer.
struct OverlaySettings: Codable, Equatable, Sendable {
    /// Valid ranges for the tunable values, shared by the decoder and the Settings UI.
    enum Limits {
        static let scale: ClosedRange<Double> = 0.5...2.0
        static let opacity: ClosedRange<Double> = 0.2...1.0
        static let horizontalOffset: ClosedRange<Double> = -600...600
        static let verticalOffset: ClosedRange<Double> = -200...600
    }

    /// Whether the overlay window should exist at all.
    var isEnabled: Bool

    /// Which screen edge the overlay hangs from.
    var anchor: OverlayAnchor

    /// Multiplier applied to `AppConstants.Overlay.baseSize`.
    var scale: Double

    /// Window alpha, applied by the SwiftUI content.
    var opacity: Double

    /// Points to shift the overlay horizontally. Positive moves right.
    var horizontalOffset: Double

    /// Points to shift the overlay vertically. Positive moves down.
    var verticalOffset: Double

    /// When `true` the overlay never receives mouse events, so clicks pass through
    /// to whatever application is underneath.
    var isClickThrough: Bool

    /// When `true` the overlay is visible on every Space and over full-screen apps.
    var joinsAllSpaces: Bool

    /// When `true` the overlay anchors to the physical top edge of the display
    /// rather than to the area below the menu bar.
    var anchorsToScreenEdge: Bool

    /// Which charm hangs on the end of the rope.
    var charm: CharmID

    /// Nudges that cancel `AppConstants.Overlay.edgeInset` exactly, which is what
    /// puts a top-trailing overlay flush into the corner of the display rather than
    /// a margin away from it. Any larger value clamps to the same place; these are
    /// the smallest that say what they mean.
    private static let flushToCorner = AppConstants.Overlay.edgeInset

    /// The shipped defaults: the charm hangs from the top-right corner of the
    /// display, tight against the physical edge above the menu bar.
    init(
        isEnabled: Bool = true,
        anchor: OverlayAnchor = .topTrailing,
        scale: Double = 1.0,
        opacity: Double = 1.0,
        horizontalOffset: Double = flushToCorner,
        verticalOffset: Double = -flushToCorner,
        isClickThrough: Bool = true,
        joinsAllSpaces: Bool = true,
        anchorsToScreenEdge: Bool = true,
        charm: CharmID = .builtIn(.daruma)
    ) {
        self.isEnabled = isEnabled
        self.anchor = anchor
        self.scale = scale.clamped(to: Limits.scale)
        self.opacity = opacity.clamped(to: Limits.opacity)
        self.horizontalOffset = horizontalOffset.clamped(to: Limits.horizontalOffset)
        self.verticalOffset = verticalOffset.clamped(to: Limits.verticalOffset)
        self.isClickThrough = isClickThrough
        self.joinsAllSpaces = joinsAllSpaces
        self.anchorsToScreenEdge = anchorsToScreenEdge
        self.charm = charm
    }

    /// Tolerant decoding: unknown or missing keys fall back to the default value and
    /// out-of-range numbers are clamped, so a settings file written by an older (or
    /// newer) build can never crash or corrupt the running app.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = OverlaySettings()

        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? fallback.isEnabled,
            // `try?` rather than `try`: an unrecognised case throws, and a raw value
            // written by a newer build must degrade to the default rather than
            // discarding every other preference alongside it.
            anchor: (try? container.decodeIfPresent(OverlayAnchor.self, forKey: .anchor)) ?? fallback.anchor,
            scale: try container.decodeIfPresent(Double.self, forKey: .scale) ?? fallback.scale,
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? fallback.opacity,
            horizontalOffset: try container.decodeIfPresent(Double.self, forKey: .horizontalOffset)
                ?? fallback.horizontalOffset,
            verticalOffset: try container.decodeIfPresent(Double.self, forKey: .verticalOffset)
                ?? fallback.verticalOffset,
            isClickThrough: try container.decodeIfPresent(Bool.self, forKey: .isClickThrough)
                ?? fallback.isClickThrough,
            joinsAllSpaces: try container.decodeIfPresent(Bool.self, forKey: .joinsAllSpaces)
                ?? fallback.joinsAllSpaces,
            anchorsToScreenEdge: try container.decodeIfPresent(Bool.self, forKey: .anchorsToScreenEdge)
                ?? fallback.anchorsToScreenEdge,
            charm: (try? container.decodeIfPresent(CharmID.self, forKey: .charm)) ?? fallback.charm
        )
    }
}
