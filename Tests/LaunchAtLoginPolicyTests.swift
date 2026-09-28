//
//  LaunchAtLoginPolicyTests.swift
//  HanglyTests
//

import Foundation
import Testing

@testable import Hangly

/// The app ships with launch-at-login on, which means the default has to act on the
/// system exactly once and never again. Getting that wrong in either direction is
/// invisible until it annoys someone: too eager and it overrides a user who turned
/// it off, too shy and a fresh install never registers at all.
@Suite("Launch at login policy")
struct LaunchAtLoginPolicyTests {
    @Test("A fresh install registers the login item")
    func firstRunRegisters() {
        #expect(
            LaunchAtLoginPolicy.decide(isFirstRun: true, stored: true, registered: false) == .register
        )
    }

    @Test("A fresh install whose login item is somehow already registered does nothing")
    func firstRunAlreadyRegistered() {
        #expect(
            LaunchAtLoginPolicy.decide(isFirstRun: true, stored: true, registered: true) == .doNothing
        )
    }

    @Test("Turning it off stays off across relaunches")
    func choiceSurvivesRelaunch() {
        // The user switched it off: the document still says on until the next launch
        // reconciles, and that launch must follow the system rather than re-register.
        #expect(
            LaunchAtLoginPolicy.decide(isFirstRun: false, stored: true, registered: false) == .follow(false)
        )
        // And once reconciled, it stays settled.
        #expect(
            LaunchAtLoginPolicy.decide(isFirstRun: false, stored: false, registered: false) == .doNothing
        )
    }

    @Test("Turning it on outside the app is picked up")
    func externalEnableIsFollowed() {
        #expect(
            LaunchAtLoginPolicy.decide(isFirstRun: false, stored: false, registered: true) == .follow(true)
        )
    }

    @Test("A shipped default of off never registers anything")
    func defaultOffNeverRegisters() {
        // Guards the rule rather than today's default: if the default is ever turned
        // back off, a first run must not register on the strength of the system's
        // leftover state either.
        #expect(
            LaunchAtLoginPolicy.decide(isFirstRun: true, stored: false, registered: false) == .doNothing
        )
        #expect(
            LaunchAtLoginPolicy.decide(isFirstRun: true, stored: false, registered: true) == .follow(true)
        )
    }

    @Test("Agreement is always left alone, whatever the run")
    func agreementIsNeverDisturbed() {
        for isFirstRun in [true, false] {
            for state in [true, false] {
                #expect(
                    LaunchAtLoginPolicy.decide(isFirstRun: isFirstRun, stored: state, registered: state)
                        == .doNothing
                )
            }
        }
    }

    @Test("The shipped default is on, which is what makes an install launch at login")
    func shippedDefaultIsOn() {
        #expect(AppSettings().launchAtLogin)
    }
}
