//
//  AudioService.swift
//  Hangly
//
//  Plays charm sound effects.
//

import AVFoundation
import Foundation
import OSLog

/// Sound effects, gated by the user's settings.
///
/// The audio engine is started on the first sound and stopped again a few seconds
/// after the last one, because a running engine keeps a render thread awake and
/// that alone would break the idle CPU budget. Buffers are synthesized once and
/// cached. If the engine cannot start — no output device, permission oddities —
/// the service marks itself unavailable and stays silent rather than retrying on
/// every swing.
@MainActor
final class AudioService {
    private let settingsStore: SettingsStore
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffers: [CharmSound: AVAudioPCMBuffer] = [:]
    private var lastPlayTime: TimeInterval = 0
    private var idleStopTask: Task<Void, Never>?

    /// `false` after the engine has refused to start.
    private(set) var isAvailable = true

    /// Two sounds inside this window collapse into one; a fast flick otherwise
    /// produces a stutter of clinks.
    private static let cooldown: TimeInterval = 0.12

    /// Silence for this long stops the engine.
    private static let idleTimeout: TimeInterval = 3

    private static let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynthesizer.sampleRate, channels: 1)

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    var isEnabled: Bool {
        settingsStore.settings.soundEffectsEnabled
    }

    /// Whether the engine is currently running, for tests and the debug read-out.
    var isEngineRunning: Bool {
        engine?.isRunning ?? false
    }

    /// Plays a material's sound.
    /// - Parameter intensity: 0...1 multiplier on the user's volume; a hard swing
    ///   is louder than a gentle one.
    func play(_ sound: CharmSound, intensity: Double = 1) {
        guard isAvailable, isEnabled else { return }

        let volume = settingsStore.settings.soundVolume * intensity.clamped(to: 0...1)
        guard volume > 0.005 else { return }

        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastPlayTime >= Self.cooldown else { return }
        lastPlayTime = now

        do {
            let (engine, player) = try ensureEngineRunning()
            guard let buffer = buffer(for: sound) else { return }
            player.volume = Float(volume)
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in
                Task { @MainActor [weak self] in
                    self?.scheduleIdleStop()
                }
            }
            if !player.isPlaying {
                player.play()
            }
            _ = engine
        } catch {
            isAvailable = false
            Logger.app.error("Audio unavailable; sounds disabled: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stops the engine now. Called at shutdown.
    func stop() {
        idleStopTask?.cancel()
        idleStopTask = nil
        player?.stop()
        engine?.stop()
    }

    // MARK: - Engine

    private func ensureEngineRunning() throws -> (AVAudioEngine, AVAudioPlayerNode) {
        let engine = self.engine ?? AVAudioEngine()
        let player = self.player ?? AVAudioPlayerNode()

        if self.engine == nil {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.format)
            self.engine = engine
            self.player = player
        }
        if !engine.isRunning {
            try engine.start()
        }
        return (engine, player)
    }

    private func buffer(for sound: CharmSound) -> AVAudioPCMBuffer? {
        if let cached = buffers[sound] { return cached }

        let samples = SoundSynthesizer.samples(for: sound)
        guard let format = Self.format,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }

        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                channel.update(from: base, count: samples.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        buffers[sound] = buffer
        return buffer
    }

    /// Stops the engine after a quiet spell, so an idle app has no render thread.
    private func scheduleIdleStop() {
        idleStopTask?.cancel()
        idleStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleTimeout))
            guard !Task.isCancelled, let self else { return }
            let since = Date().timeIntervalSinceReferenceDate - self.lastPlayTime
            guard since >= Self.idleTimeout - 0.05 else { return }
            self.player?.stop()
            self.engine?.stop()
        }
    }
}
