//
//  ObservationStream.swift
//  Hangly
//
//  Bridges the Observation framework to structured concurrency.
//

import Foundation
import Observation

/// Turns changes to an `@Observable` object into an `AsyncStream`.
///
/// SwiftUI observes `@Observable` types for free, but plain services — such as the
/// AppKit window controller that owns the overlay panel — have no equivalent. This
/// type re-arms `withObservationTracking` after every change and republishes the
/// produced value, so a service can simply write:
///
/// ```swift
/// for await overlay in stream.values { apply(overlay) }
/// ```
///
/// Only the properties actually read inside `producer` are tracked, so the stream
/// stays quiet when unrelated state changes.
@MainActor
final class ObservationStream<Value: Sendable> {
    /// Values produced on every observed change, starting with the current value.
    let values: AsyncStream<Value>

    private let producer: @MainActor () -> Value
    private var continuation: AsyncStream<Value>.Continuation?
    private var isStarted = false

    /// - Parameter producer: Reads the observable state of interest. Every
    ///   `@Observable` property it touches becomes part of the tracked set.
    init(producer: @escaping @MainActor () -> Value) {
        self.producer = producer
        // Only the newest value matters for settings-style state; an unbounded
        // buffer would replay a backlog of stale frames after a slow consumer.
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.values = stream
        self.continuation = continuation
    }

    /// Emits the current value and begins tracking. Safe to call more than once.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        emit()
    }

    /// Ends the stream and stops re-arming observation.
    func stop() {
        continuation?.finish()
        continuation = nil
    }

    private func emit() {
        guard let continuation else { return }

        let value = withObservationTracking {
            producer()
        } onChange: {
            // `onChange` fires *before* the mutation is visible, so hop to the next
            // main-actor turn to read the settled value.
            Task { @MainActor [weak self] in
                self?.emit()
            }
        }

        continuation.yield(value)
    }
}
