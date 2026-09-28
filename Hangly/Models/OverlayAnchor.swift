//
//  OverlayAnchor.swift
//  Hangly
//
//  Where the overlay is pinned inside its screen.
//

import Foundation

/// Screen-edge anchor for the floating overlay.
///
/// Phase 1 ships the top row only — `topCenter` is the default and satisfies the
/// "pinned to top center" requirement. The extra cases exist so that additional
/// placements (and, later, per-display placement) do not require a redesign of
/// the placement pipeline.
enum OverlayAnchor: String, CaseIterable, Codable, Sendable, Identifiable {
    case topLeading
    case topCenter
    case topTrailing

    var id: String { rawValue }

    /// Horizontal component of the anchor, consumed by `ScreenPlacement`.
    enum Horizontal: Sendable {
        case leading
        case center
        case trailing
    }

    var horizontal: Horizontal {
        switch self {
        case .topLeading: .leading
        case .topCenter: .center
        case .topTrailing: .trailing
        }
    }

    /// Human-readable name used by the Settings window.
    var displayName: String {
        switch self {
        case .topLeading: "Top Left"
        case .topCenter: "Top Center"
        case .topTrailing: "Top Right"
        }
    }
}
