//
//  NSScreen+Hangly.swift
//  Hangly
//
//  Screen selection for the overlay.
//

import AppKit

extension NSScreen {
    /// The display the overlay hangs from.
    ///
    /// `NSScreen.screens.first` is the primary display — the one that owns the menu
    /// bar and the global coordinate origin — which keeps the overlay in a stable,
    /// predictable place. `NSScreen.main` is deliberately *not* used: it follows
    /// keyboard focus, so the overlay would hop between displays as the user moved
    /// between apps. Per-display selection is Phase 2 work.
    static var hanglyPreferred: NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    /// The region the overlay is placed within.
    /// - Parameter ignoringMenuBar: When `true`, use the full physical bounds so the
    ///   overlay can hang from the very top edge. When `false`, use `visibleFrame`,
    ///   which starts below the menu bar.
    func hanglyPlacementBounds(ignoringMenuBar: Bool) -> CGRect {
        ignoringMenuBar ? frame : visibleFrame
    }
}
