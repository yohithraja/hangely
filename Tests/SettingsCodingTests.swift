//
//  SettingsCodingTests.swift
//  HanglyTests
//

import Foundation
import Testing

@testable import Hangly

/// The settings document is written to disk, so it must survive being written by a
/// different build of the app. These tests pin the tolerant-decoding behaviour.
@Suite("Settings coding")
struct SettingsCodingTests {
    private func decodeOverlay(_ json: String) throws -> OverlaySettings {
        try JSONDecoder().decode(OverlaySettings.self, from: Data(json.utf8))
    }

    @Test("An empty document decodes to the shipped defaults")
    func emptyDocumentUsesDefaults() throws {
        let decoded = try decodeOverlay("{}")

        #expect(decoded == OverlaySettings())
    }

    @Test("A partial document keeps the stored value and defaults the rest")
    func partialDocumentDefaultsMissingKeys() throws {
        let decoded = try decodeOverlay(#"{"opacity": 0.5}"#)

        #expect(decoded.opacity == 0.5)
        #expect(decoded.anchor == OverlaySettings().anchor)
        #expect(decoded.isClickThrough == OverlaySettings().isClickThrough)
    }

    @Test("Keys written by a newer build are ignored instead of throwing")
    func unknownKeysAreIgnored() throws {
        let decoded = try decodeOverlay(#"{"ropeSegmentCount": 24, "opacity": 0.8}"#)

        #expect(decoded.opacity == 0.8)
    }

    @Test("Out-of-range numbers are clamped to the supported range")
    func outOfRangeValuesAreClamped() throws {
        let tooBig = try decodeOverlay(#"{"scale": 99, "opacity": 4}"#)
        let tooSmall = try decodeOverlay(#"{"scale": -99, "opacity": -4}"#)

        #expect(tooBig.scale == OverlaySettings.Limits.scale.upperBound)
        #expect(tooBig.opacity == OverlaySettings.Limits.opacity.upperBound)
        #expect(tooSmall.scale == OverlaySettings.Limits.scale.lowerBound)
        #expect(tooSmall.opacity == OverlaySettings.Limits.opacity.lowerBound)
    }

    @Test("Encoding then decoding returns an identical value")
    func roundTripIsLossless() throws {
        let original = AppSettings(
            overlay: OverlaySettings(
                isEnabled: false,
                anchor: .topTrailing,
                scale: 1.4,
                opacity: 0.6,
                horizontalOffset: -120,
                verticalOffset: 48,
                isClickThrough: false,
                joinsAllSpaces: false,
                anchorsToScreenEdge: true
            ),
            launchAtLogin: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded == original)
    }

    @Test("Sound settings default on at a gentle volume and clamp when decoded")
    func soundSettingsDecode() throws {
        let defaults = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(defaults.soundEffectsEnabled)
        #expect(defaults.soundVolume > 0.05)
        #expect(defaults.soundVolume < 0.3)

        let loud = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"soundVolume": 9}"#.utf8))
        #expect(loud.soundVolume == 1)

        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"soundEffectsEnabled": false}"#.utf8))
        #expect(off.soundEffectsEnabled == false)
    }

    @Test("A document with no schema version is treated as the current schema")
    func missingSchemaVersionDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        #expect(decoded.schemaVersion == AppSettings.currentSchemaVersion)
        #expect(decoded.overlay == OverlaySettings())
        #expect(decoded.launchAtLogin == AppSettings().launchAtLogin)
    }
}
