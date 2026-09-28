//
//  CharmLibraryPresenter.swift
//  Hangly
//
//  Opens and focuses the Charm Library window from an accessory app.
//

import AppKit
import SwiftUI

/// Brings the Charm Library window to the front.
///
/// Same sequence as the Settings presenter, for the same reason: an accessory app is
/// outside the normal activation order, so open the scene, activate, then raise
/// the window on the next main-actor turn once SwiftUI has created it.
@MainActor
final class CharmLibraryPresenter {
    func present(using openWindow: OpenWindowAction) {
        NSApp.activate()
        openWindow(id: CharmLibraryView.windowID)

        Task { @MainActor [weak self] in
            self?.raiseWindow()
        }
    }

    private func raiseWindow() {
        let window = NSApp.windows.first { window in
            window.identifier?.rawValue == CharmLibraryView.windowID || window.title == "Charm Library"
        }
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
