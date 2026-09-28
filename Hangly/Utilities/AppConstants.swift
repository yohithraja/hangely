//
//  AppConstants.swift
//  Hangly
//
//  Compile-time configuration that has no business living in a view.
//

import CoreGraphics
import Foundation

/// Namespaced constants. Framework-free on purpose: nothing here imports AppKit or
/// SwiftUI, so the constants stay usable from tests and from background code.
enum AppConstants {
    static let appName = "Hangly"

    /// The running bundle identifier, with a literal fallback for unit-test bundles.
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.hangly.Hangly"
    }

    /// Marketing version, e.g. "1.0.0".
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// Build number, e.g. "1".
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// The bundle's copyright line. Read rather than written here, so `Info.plist`
    /// stays the one place it is stated and the About window can never disagree
    /// with what Finder's Get Info shows.
    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026. sharancreatedthis."
    }

    enum Defaults {
        /// Versioned so a future schema change can live alongside the old document.
        static let settingsStorageKey = "com.hangly.settings.v1"
    }

    enum Overlay {
        /// Unscaled overlay size. The effective size is this multiplied by
        /// `OverlaySettings.scale`.
        ///
        /// Large enough that a charm dragged to the horizontal clears the window on
        /// either side, charm included — the charm turns with the cord, so at full
        /// reach it hangs outward rather than down. The extra area costs nothing
        /// visually: the panel is transparent and click-through everywhere the
        /// rope is not.
        static let baseSize = CGSize(width: 740, height: 420)

        /// Margin kept between the overlay and the screen edges.
        static let edgeInset: CGFloat = 12
    }

    /// Developer-facing switches. Deliberately not exposed in Settings.
    ///
    /// Enable with either of:
    ///
    ///     defaults write com.hangly.Hangly HanglyDebugRope -bool YES
    ///
    /// or by adding `-HanglyDebugRope YES` to the scheme's launch arguments.
    /// The value is re-read a few times a second, so it takes effect live.
    #if !HANGLY_PRODUCTION
    enum Debug {
        static let ropeOverlayKey = "HanglyDebugRope"
    }
    #endif

    enum SettingsWindow {
        /// Identifier SwiftUI assigns to the window created by the `Settings` scene.
        /// Used to raise that window from a menu bar app, which does not otherwise
        /// come to the front.
        static let identifier = "com_apple_SwiftUI_Settings_window"
    }
}
