//
//  OverlayPanel.swift
//  Hangly
//
//  The transparent, click-through, always-on-top window.
//

import AppKit

/// Borderless non-activating panel that hosts the overlay content.
///
/// Every requirement of the floating overlay is expressed here:
///
/// - **Transparent** — `isOpaque = false` plus a clear background, so only what
///   SwiftUI draws is visible.
/// - **Above all apps** — `.statusBar` level sits above normal and floating windows
///   of every other application, while staying below system menus and alerts.
/// - **Click-through** — `ignoresMouseEvents` means the window never hit-tests, so
///   clicks land on whatever is underneath.
/// - **Never steals focus** — `.nonactivatingPanel` plus `canBecomeKey == false`
///   keeps the user's current app active and the text caret where it was.
///
/// `NSPanel` rather than `NSWindow` because only a panel supports
/// `.nonactivatingPanel`.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true

        level = .statusBar
        collectionBehavior = Self.collectionBehavior(joinsAllSpaces: true)

        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true

        // The overlay is repositioned programmatically; implicit animation would
        // make it visibly slide after a display change.
        animationBehavior = .none

        identifier = NSUserInterfaceItemIdentifier("com.hangly.window.overlay")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OverlayPanel is created in code and never decoded from a nib.")
    }

    /// A click-through overlay must never become key or main, or it would pull focus
    /// away from the app the user is actually working in.
    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    /// - Parameter joinsAllSpaces: When `true` the panel is visible on every Space
    ///   and alongside full-screen apps. When `false` it follows the active Space.
    static func collectionBehavior(joinsAllSpaces: Bool) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [
            .stationary,          // Do not move during Mission Control transitions.
            .ignoresCycle,        // Skip in Cmd-Tab and window cycling.
            .fullScreenAuxiliary  // Allowed to appear over full-screen apps.
        ]

        // `.canJoinAllSpaces` and `.moveToActiveSpace` are mutually exclusive.
        behavior.insert(joinsAllSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        return behavior
    }
}
