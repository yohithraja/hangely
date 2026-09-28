//
//  AudioTests.swift
//  HanglyTests
//

import Foundation
import Testing

@testable import Hangly

/// The sounds are synthesized, so their shape can be asserted exactly.
@Suite("Sound synthesis")
struct SoundSynthesizerTests {
    @Test("Every material produces a finite, bounded, non-silent sound")
    func everyMaterialSounds() {
        for sound in CharmSound.allCases {
            let samples = SoundSynthesizer.samples(for: sound)
            let seconds = Double(samples.count) / SoundSynthesizer.sampleRate

            #expect(seconds > 0.04, "\(sound) is too short")
            #expect(seconds < 2.0, "\(sound) is too long")
            #expect(samples.allSatisfy { $0.isFinite })
            #expect(samples.allSatisfy { abs($0) <= 1.0 })
            #expect(samples.contains { abs($0) > 0.1 }, "\(sound) is silent")
        }
    }

    @Test("Synthesis is deterministic")
    func synthesisIsDeterministic() {
        for sound in CharmSound.allCases {
            let first = SoundSynthesizer.samples(for: sound)
            let second = SoundSynthesizer.samples(for: sound)
            #expect(first == second)
        }
    }

    @Test("A bell rings longer than a knock and decays rather than stopping")
    func bellRingsAndDecays() {
        let bell = SoundSynthesizer.samples(for: .bell)
        let wood = SoundSynthesizer.samples(for: .wood)
        #expect(bell.count > wood.count * 8)

        // It decays: the last tenth is well below the first tenth.
        let tenth = bell.count / 10
        let head = bell.prefix(tenth).map { abs($0) }.max() ?? 0
        let tail = bell.suffix(tenth).map { abs($0) }.max() ?? 0
        #expect(tail < head * 0.5)

        // And it never ends on a cut: the final few milliseconds are near silence,
        // which is what stops a still-ringing bell from clicking when it stops.
        let lastMoment = Int(0.005 * SoundSynthesizer.sampleRate)
        for sound in CharmSound.allCases {
            let samples = SoundSynthesizer.samples(for: sound)
            let ending = samples.suffix(lastMoment).map { abs($0) }.max() ?? 0
            #expect(ending < 0.03, "\(sound) ends abruptly at \(ending)")
        }
    }

    @Test("Normalisation lands the peak where asked and leaves silence alone")
    func normalisation() {
        let loud = SoundSynthesizer.normalized([0.1, -0.5, 0.25], peak: 0.8)
        #expect(abs((loud.map { abs($0) }.max() ?? 0) - 0.8) < 1e-6)
        #expect(SoundSynthesizer.normalized([0, 0, 0], peak: 0.8) == [0, 0, 0])
    }
}

/// Which charms make which sounds, and that the service stays quiet when told to.
@Suite("Charm sounds")
@MainActor
struct CharmSoundTests {
    @Test("Materials are assigned as the brief describes")
    func materials() {
        #expect(BuiltInCharms.charm(for: .ghanta).sound == .bell)
        #expect(BuiltInCharms.charm(for: .daruma).sound == .wood)
        #expect(BuiltInCharms.charm(for: .manekiNeko).sound == .wood)
        #expect(BuiltInCharms.charm(for: .drishtiBommai).sound == .wood)
        #expect(BuiltInCharms.charm(for: .horseshoe).sound == .metal)
        #expect(BuiltInCharms.charm(for: .nazar).sound == .glass)
        #expect(BuiltInCharms.charm(for: .himmeli).sound == .soft)
        #expect(BuiltInCharms.charm(for: .star).sound == .soft)
    }

    @Test("Exactly one built-in charm is a bell")
    func oneBell() {
        #expect(BuiltInCharms.all.filter { $0.sound == .bell }.count == 1)
    }

    @Test("Sounds are off when the setting is off, and the engine never starts")
    func disabledIsSilent() throws {
        let suite = "com.hangly.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, storageKey: "settings")
        store.update { $0.soundEffectsEnabled = false }

        let audio = AudioService(settingsStore: store)
        audio.play(.bell)

        #expect(audio.isEngineRunning == false)
        #expect(audio.isAvailable)
    }

    @Test("Zero volume plays nothing either")
    func zeroVolumeIsSilent() throws {
        let suite = "com.hangly.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, storageKey: "settings")
        store.update { $0.soundVolume = 0 }

        let audio = AudioService(settingsStore: store)
        audio.play(.wood)

        #expect(audio.isEngineRunning == false)
    }
}
