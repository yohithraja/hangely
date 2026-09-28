//
//  LaunchAtLoginPolicy.swift
//  Hangly
//
//  Who wins when the stored preference and the login item disagree.
//

import Foundation

/// What launching the app should do about its login item.
enum LaunchAtLoginDecision: Equatable {
    /// The preference and the system already agree.
    case doNothing

    /// Register the login item, because the shipped default asks for it and the
    /// user has not yet said otherwise.
    case register

    /// Take the system's word for it and write that into the preference.
    case follow(Bool)
}

/// Decides between the shipped default and what the system actually has registered.
///
/// The rule is one sentence: the default applies once, and the user's choice applies
/// forever after. On a first run there is no stored preference, so the default is the
/// only statement of intent and the login item is registered to match it. From the
/// second run on, the system is the source of truth — turning the login item off in
/// Settings, in System Settings, or by moving the app must all stick, and none of
/// them would if the default were reapplied at every launch.
///
/// Pure on purpose: this is the part that is easy to get subtly wrong and impossible
/// to notice, so it is decided here where it can be tested, not inside the launch
/// sequence where it cannot.
enum LaunchAtLoginPolicy {
    /// - Parameters:
    ///   - isFirstRun: Whether this launch found no settings document.
    ///   - stored: What the settings document says, or the shipped default on a first run.
    ///   - registered: Whether the system currently has the login item registered.
    static func decide(isFirstRun: Bool, stored: Bool, registered: Bool) -> LaunchAtLoginDecision {
        guard stored != registered else { return .doNothing }

        // The one moment the default gets to act on the system rather than the
        // other way round.
        if isFirstRun, stored {
            return .register
        }
        return .follow(registered)
    }
}
