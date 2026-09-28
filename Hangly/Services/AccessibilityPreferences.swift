//
//  AccessibilityPreferences.swift
//  Hangly
//
//  System accessibility settings the overlay respects.
//

import AppKit
import Observation

/// Mirrors the system's Reduce Motion preference and follows changes to it.
///
/// SwiftUI views read `accessibilityReduceMotion` from the environment; the AppKit
/// side — the overlay's fades and the charm cross-fade — reads this instead. It is
/// observable, so a change in System Settings takes effect without a relaunch.
@MainActor
@Observable
final class AccessibilityPreferences {
    private(set) var reducesMotion: Bool

    @ObservationIgnored private var token: (any NSObjectProtocol)?

    init() {
        reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func start() {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stop() {
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        token = nil
    }

    func refresh() {
        let current = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if current != reducesMotion {
            reducesMotion = current
        }
    }
}
