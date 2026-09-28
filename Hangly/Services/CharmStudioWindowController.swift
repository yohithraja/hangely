//
//  CharmStudioWindowController.swift
//  Hangly
//
//  Hosts the Studio in an AppKit window any service can open.
//

import AppKit
import SwiftUI

/// Owns the single Studio window.
///
/// An `NSWindow` around an `NSHostingController` rather than a SwiftUI `Window`
/// scene, for the same reason the overlay is an `NSPanel`: it can be opened, given a
/// file and raised from any service without threading an `OpenWindowAction` through
/// the view hierarchy. The view tree is released when the window closes, so a hidden
/// Studio cannot keep its rope preview ticking.
@MainActor
final class CharmStudioWindowController: NSObject, NSWindowDelegate {
    static let frameAutosaveName = "CharmStudio"

    private let viewModel: CharmStudioViewModel
    private var window: NSWindow?

    init(viewModel: CharmStudioViewModel) {
        self.viewModel = viewModel
        super.init()
        viewModel.onRequestClose = { [weak self] in
            self?.window?.close()
        }
    }

    /// Shows the Studio, loading `url` into it if given.
    func present(url: URL? = nil) {
        NSApp.activate()
        let window = ensureWindow()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        if let url {
            Task { await viewModel.open(url: url) }
        }
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            if window.contentViewController == nil {
                window.contentViewController = makeHostingController()
            }
            return window
        }

        let window = NSWindow(contentViewController: makeHostingController())
        window.title = "AI Charm Studio"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1000, height: 660))
        window.minSize = NSSize(width: 880, height: 560)
        window.center()
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }

    private func makeHostingController() -> NSHostingController<CharmStudioView> {
        NSHostingController(rootView: CharmStudioView(viewModel: viewModel))
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the view tree so no preview timeline runs in a closed window.
        window?.contentViewController = nil
    }
}
