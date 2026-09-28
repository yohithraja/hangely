//
//  SoundSynthesizer.swift
//  Hangly
//
//  Generates the charm sound effects from first principles.
//

import Foundation

/// Produces mono PCM samples for each `CharmSound`.
///
/// Additive synthesis: a sum of exponentially decaying sine partials, plus a little
/// filtered noise for the percussive materials. Everything is deterministic — the
/// noise comes from a fixed-seed generator — so a test can assert on the output and
/// two launches sound identical. The results are a few hundred kilobytes in total,
/// generated once and cached.
enum SoundSynthesizer {
    static let sampleRate = 44_100.0

    /// One sine component of a struck object.
    struct Partial {
        /// Multiple of the fundamental. Inharmonic ratios are what make metal and
        /// bells sound like themselves rather than like organ notes.
        let ratio: Double
        let amplitude: Double
        /// Time constant of the exponential decay, in seconds.
        let decay: Double
    }

    /// A recipe: a fundamental, its partials, and how long the sound lasts.
    struct Voice {
        let fundamental: Double
        let partials: [Partial]
        let duration: Double
        /// Linear fade-in so the onset does not click.
        let attack: Double
    }

    /// Full-scale samples in `-1...1`, peak-normalised per sound.
    static func samples(for sound: CharmSound) -> [Float] {
        switch sound {
        case .bell:
            return normalized(render(bell), peak: 0.85)
        case .glass:
            return normalized(render(glass), peak: 0.7)
        case .metal:
            return normalized(render(metal), peak: 0.75)
        case .wood:
            let knock = noiseBurst(duration: 0.07, decay: 0.012, smoothing: 0.25, gain: 0.7)
            return normalized(mix(knock, render(wood)), peak: 0.8)
        case .soft:
            let rustle = noiseBurst(duration: 0.09, decay: 0.006, smoothing: 0.08, gain: 0.15)
            return normalized(mix(render(soft), rustle), peak: 0.5)
        }
    }

    // MARK: - Recipes

    static let bell = Voice(
        fundamental: 1046,
        partials: [
            Partial(ratio: 1.00, amplitude: 1.00, decay: 1.30),
            Partial(ratio: 2.00, amplitude: 0.55, decay: 0.90),
            Partial(ratio: 2.41, amplitude: 0.40, decay: 0.70),
            Partial(ratio: 3.00, amplitude: 0.30, decay: 0.50),
            Partial(ratio: 4.52, amplitude: 0.18, decay: 0.35),
            Partial(ratio: 5.19, amplitude: 0.10, decay: 0.25)
        ],
        duration: 1.5,
        attack: 0.003
    )

    static let glass = Voice(
        fundamental: 2600,
        partials: [
            Partial(ratio: 1.00, amplitude: 1.0, decay: 0.28),
            Partial(ratio: 1.90, amplitude: 0.5, decay: 0.20),
            Partial(ratio: 2.75, amplitude: 0.3, decay: 0.14)
        ],
        duration: 0.35,
        attack: 0.001
    )

    static let metal = Voice(
        fundamental: 1800,
        partials: [
            Partial(ratio: 1.00, amplitude: 1.00, decay: 0.45),
            Partial(ratio: 1.56, amplitude: 0.60, decay: 0.32),
            Partial(ratio: 2.31, amplitude: 0.35, decay: 0.22),
            Partial(ratio: 3.10, amplitude: 0.20, decay: 0.15)
        ],
        duration: 0.55,
        attack: 0.001
    )

    static let wood = Voice(
        fundamental: 190,
        partials: [
            Partial(ratio: 1.0, amplitude: 1.0, decay: 0.03),
            Partial(ratio: 1.7, amplitude: 0.4, decay: 0.02)
        ],
        duration: 0.07,
        attack: 0.0005
    )

    static let soft = Voice(
        fundamental: 160,
        partials: [Partial(ratio: 1, amplitude: 1, decay: 0.045)],
        duration: 0.09,
        attack: 0.002
    )

    // MARK: - Building blocks

    /// Tail fade so a still-ringing sound never ends on a cut, which would click.
    static let release = 0.12

    /// Decaying sines at `fundamental * ratio`, with a short linear attack and a
    /// release fade over the final stretch of the buffer.
    static func render(_ voice: Voice) -> [Float] {
        let count = Int(voice.duration * sampleRate)
        let release = min(Self.release, voice.duration * 0.3)
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let attack = voice.attack > 0 ? min(1, time / voice.attack) : 1
            let fade = min(1, (voice.duration - time) / release)
            let envelope = attack * max(0, fade)
            var value = 0.0
            for partial in voice.partials {
                let amplitude = partial.amplitude * exp(-time / partial.decay)
                value += amplitude * sin(2 * .pi * voice.fundamental * partial.ratio * time)
            }
            output[index] = Float(value * envelope)
        }
        return output
    }

    /// White noise from a fixed-seed generator, one-pole low-passed and decayed.
    static func noiseBurst(duration: Double, decay: Double, smoothing: Double, gain: Double) -> [Float] {
        let count = Int(duration * sampleRate)
        var output = [Float](repeating: 0, count: count)
        var state: UInt32 = 0x9E37_79B9
        var filtered = 0.0
        for index in 0..<count {
            // Linear congruential generator: deterministic and plenty for noise.
            state = state &* 1_664_525 &+ 1_013_904_223
            let white = (Double(state) / Double(UInt32.max) * 2) - 1
            filtered += smoothing * (white - filtered)
            let time = Double(index) / sampleRate
            output[index] = Float(filtered * exp(-time / decay) * gain)
        }
        return output
    }

    static func mix(_ first: [Float], _ second: [Float]) -> [Float] {
        let count = max(first.count, second.count)
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let left = index < first.count ? first[index] : 0
            let right = index < second.count ? second[index] : 0
            output[index] = left + right
        }
        return output
    }

    /// Scales so the loudest sample sits at `peak`, leaving headroom for mixing.
    static func normalized(_ samples: [Float], peak: Float) -> [Float] {
        guard let loudest = samples.map({ abs($0) }).max(), loudest > 0 else { return samples }
        let scale = peak / loudest
        return samples.map { $0 * scale }
    }
}
