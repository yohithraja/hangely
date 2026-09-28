//
//  AppDelegate.swift
//  Hangly
//
//  AppKit lifecycle hooks that SwiftUI's App protocol does not expose.
//

import AppKit
import OSLog

/// Owns the `AppEnvironment` and drives its lifecycle.
///
/// The delegate — not the `App` struct — is the owner because it is the only place
/// with a guaranteed "launched" and "about to terminate" callback. Creating the
/// object graph here also means services start *after* AppKit is ready, so the
/// overlay panel is never created before the window server can place it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The composition root, read by `HanglyApp` when it builds its scenes.
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `LSUIElement` in Info.plist already makes Hangly an accessory app with no
        // Dock icon. Setting the policy again is harmless and keeps the behaviour
        // correct even if the app is launched in a way that bypasses the plist.
        NSApp.setActivationPolicy(.accessory)

        environment.bootstrap()
        Logger.app.diagnostic("Launched as a menu bar accessory.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.shutdown()
    }

    /// Closing the Settings window must not quit a menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
