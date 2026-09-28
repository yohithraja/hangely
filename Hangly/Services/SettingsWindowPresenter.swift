//
//  SettingsWindowPresenter.swift
//  Hangly
//
//  Opens and focuses the SwiftUI Settings scene from an accessory app.
//

import AppKit
import SwiftUI

/// Brings the Settings window to the front.
///
/// An `LSUIElement` app is not in the normal activation order, so calling
/// `openSettings()` alone can leave the window created but buried behind whatever
/// the user was working in. The reliable sequence is: activate the app, ask SwiftUI
/// to open the scene, then raise the resulting window on the next main-actor turn —
/// by which point SwiftUI has created it.
@MainActor
final class SettingsWindowPresenter {
    /// - Parameter openSettings: The SwiftUI environment action, which only a view
    ///   can read. Passing it in keeps AppKit out of the view layer.
    func present(using openSettings: OpenSettingsAction) {
        NSApp.activate()
        openSettings()

        Task { @MainActor [weak self] in
            self?.raiseSettingsWindow()
        }
    }

    private func raiseSettingsWindow() {
        let settingsWindow = NSApp.windows.first { window in
            window.identifier?.rawValue == AppConstants.SettingsWindow.identifier
        }

        guard let settingsWindow else { return }
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
    }
}
