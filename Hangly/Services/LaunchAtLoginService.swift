//
//  LaunchAtLoginService.swift
//  Hangly
//
//  Login-item registration via ServiceManagement.
//

import Foundation
import OSLog
import ServiceManagement

/// Abstraction over the login-item registry.
///
/// `SMAppService` talks to a system daemon and fails in predictable ways during
/// development (unsigned builds, app not in `/Applications`). Hiding it behind a
/// protocol keeps `SettingsViewModel` testable without touching the real daemon.
@MainActor
protocol LaunchAtLoginManaging: AnyObject {
    /// Whether the app is currently registered to launch at login.
    var isEnabled: Bool { get }

    /// Registers or unregisters the login item.
    /// - Throws: The underlying `SMAppService` error, which is surfaced to the user.
    func setEnabled(_ enabled: Bool) throws
}

/// Production implementation backed by `SMAppService.mainApp`.
@MainActor
final class LaunchAtLoginService: LaunchAtLoginManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            Logger.settings.diagnostic("Registered Hangly as a login item.")
        } else {
            try SMAppService.mainApp.unregister()
            Logger.settings.diagnostic("Unregistered Hangly as a login item.")
        }
    }
}
