//
//  MenuBarIcon.swift
//  Hangly
//
//  Status item artwork.
//

import AppKit
import SwiftUI

/// The status-bar image: a charm hanging from the top of the icon on a beaded cord.
///
/// Drawn rather than picked from SF Symbols, because the one thing the app does has
/// no symbol: something dangles from the menu bar. The cord starts at the very top
/// edge so the bar itself reads as what it hangs from, and the whole assembly leans
/// a few degrees, which at this size is the difference between a hanging charm and a
/// plumb line.
///
/// The charm is solid while the overlay is showing and an outline while it is
/// hidden, so the menu bar reflects app state at a glance.
struct MenuBarIcon: View {
    let viewModel: MenuBarViewModel

    var body: some View {
        Image(nsImage: MenuBarIconArtwork.image(showing: isOverlayVisible))
            .accessibilityLabel(isOverlayVisible ? "Hangly, overlay visible" : "Hangly, overlay hidden")
    }

    private var isOverlayVisible: Bool {
        viewModel.isOverlayVisible
    }
}
