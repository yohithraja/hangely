//
//  CharmDialogs.swift
//  Hangly
//
//  The few standard panels the charm system needs.
//

import AppKit
import UniformTypeIdentifiers

/// Open panel, confirmation and error alert for charm import and deletion.
///
/// Kept in one AppKit-only type so the view models stay free of `NSAlert` and
/// `NSOpenPanel`, and so a test can substitute a fake that answers without a
/// window. As an accessory app Hangly is outside the normal activation order, so
/// each panel activates the app first or it would open behind the user's work.
@MainActor
final class CharmDialogs {
    /// Panels must sit above the overlay, which floats at status-bar level.
    private static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    /// Asks for an image file. `nil` when the user cancels.
    func chooseImage() -> URL? {
        NSApp.activate()

        let panel = NSOpenPanel()
        panel.title = "Choose an Image"
        panel.message = "PNG, JPEG or WebP. The background is removed automatically."
        panel.prompt = "Import"
        panel.allowedContentTypes = CharmImageProcessor.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.level = Self.panelLevel

        return panel.runModal() == .OK ? panel.url : nil
    }

    /// - Returns: `true` when the user confirms.
    func confirmDelete(named name: String) -> Bool {
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "The charm and its image are removed from Hangly. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = Self.panelLevel

        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentError(_ error: any Error, title: String) {
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.window.level = Self.panelLevel
        alert.runModal()
    }
}
