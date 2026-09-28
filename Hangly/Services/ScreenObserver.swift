//
//  ScreenObserver.swift
//  Hangly
//
//  Publishes display-configuration changes.
//

import AppKit
import Foundation

/// Reports when the display arrangement changes — resolution, scaling, a monitor
/// being plugged in or unplugged, or the Dock/menu bar changing the visible frame.
///
/// The overlay must re-anchor on every one of these, otherwise it drifts off screen.
@MainActor
final class ScreenObserver {
    /// Fires once per display-configuration change.
    let changes: AsyncStream<Void>

    private let continuation: AsyncStream<Void>.Continuation
    private var token: (any NSObjectProtocol)?

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.changes = stream
        self.continuation = continuation
    }

    /// Begins observing. Safe to call more than once.
    func start() {
        guard token == nil else { return }

        // Captured locally so the notification block never retains `self`.
        let continuation = self.continuation
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            continuation.yield(())
        }
    }

    /// Stops observing and releases the notification token.
    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
    }
}
