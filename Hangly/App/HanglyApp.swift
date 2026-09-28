//
//  HanglyApp.swift
//  Hangly
//
//  Application entry point.
//

import SwiftUI

/// Hangly's SwiftUI entry point.
///
/// Two scenes only:
///
/// - `MenuBarExtra` is the app's whole presence. There is no `WindowGroup`, which —
///   together with `LSUIElement` — is what makes Hangly a true menu bar app with no
///   Dock icon and no main window.
/// - `Settings` gives the standard macOS Settings window and its ⌘, shortcut.
///
/// The overlay is *not* a scene. It is an AppKit `NSPanel` managed by
/// `OverlayWindowController`, because SwiftUI's `Window` scene cannot express a
/// borderless, non-activating, click-through window pinned above every other app.
@main
struct HanglyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: appDelegate.environment.menuBarViewModel)
        } label: {
            MenuBarIcon(viewModel: appDelegate.environment.menuBarViewModel)
        }
        // `.menu` renders the content as a real NSMenu: native look, keyboard
        // navigation and VoiceOver support without reimplementing any of it.
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(environment: appDelegate.environment)
        }

        // Declared after the menu bar scene so it is not treated as the primary
        // scene and opened at launch; it appears only when asked for.
        Window("Charm Library", id: CharmLibraryView.windowID) {
            CharmLibraryView(environment: appDelegate.environment)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 600)
    }
}
