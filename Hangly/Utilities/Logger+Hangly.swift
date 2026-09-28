//
//  Logger+Hangly.swift
//  Hangly
//
//  Unified-logging categories. Use `log show --predicate 'subsystem == "com.hangly.Hangly"'`.
//

import OSLog

extension Logger {
    private static let subsystem = AppConstants.bundleIdentifier

    /// Application lifecycle.
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Overlay window creation, placement and teardown.
    static let overlay = Logger(subsystem: subsystem, category: "overlay")

    /// Settings persistence and login-item registration.
    static let settings = Logger(subsystem: subsystem, category: "settings")

    /// Menu bar interactions.
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")

    /// Development diagnostics: what the app is doing, moment to moment.
    ///
    /// Compiled out of production builds entirely. The message is built inside an
    /// autoclosure that production never calls, so neither the formatting work nor
    /// the literals themselves reach the shipped binary, and nothing about a user's
    /// session can be read back with `log show` on their machine. Anything a user
    /// should be able to report — a failure, a recovery, a refusal — is logged at
    /// `error` or `warning` instead and ships.
    @inline(__always)
    func diagnostic(_ message: @autoclosure () -> String) {
        #if !HANGLY_PRODUCTION
        // Resolved into a local first: an autoclosure cannot be called from inside
        // an os_log interpolation, which captures what it is given.
        let text = message()
        info("\(text, privacy: .public)")
        #endif
    }
}
