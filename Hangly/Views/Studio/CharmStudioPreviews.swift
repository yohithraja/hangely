//
//  CharmStudioPreviews.swift
//  Hangly
//
//  The three live previews: the cut-out, the lit charm, and the charm on a rope.
//

import CoreGraphics
import SwiftUI

/// Cut-out on a checkerboard, the charm as it will render, and a swinging preview.
struct StudioPreviewPanel: View {
    let viewModel: CharmStudioViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                previewTile("Cut-out") {
                    ZStack {
                        CheckerboardView()
                        if let isolated = viewModel.isolated {
                            Image(decorative: isolated, scale: 1)
                                .resizable()
                                .scaledToFit()
                                .padding(10)
                                .accessibilityLabel("Cut-out preview")
                        }
                    }
                }
                previewTile("Charm") {
                    ZStack {
                        Color(white: 0.13)
                        if let charm = viewModel.previewCharm {
                            CharmView(charm: charm, inset: 0.8)
                                .padding(8)
                                .accessibilityLabel("Charm preview")
                        }
                    }
                }
            }
            previewTile("On the rope") {
                StudioRopePreview(charm: viewModel.previewCharm, reducesMotion: viewModel.reducesMotion)
            }
        }
        .padding(14)
    }

    private func previewTile(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary))
        }
    }
}

/// The classic transparency grid.
struct CheckerboardView: View {
    var cell = 8.0

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            var path = Path()
            var row = 0
            var y = 0.0
            while y < size.height {
                var x = row.isMultiple(of: 2) ? 0.0 : cell
                while x < size.width {
                    path.addRect(CGRect(x: x, y: y, width: cell, height: cell))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
            context.fill(path, with: .color(Color(white: 0.80)))
        }
        .accessibilityHidden(true)
    }
}

/// A private rope with the draft charm on it, stepping its own simulation.
///
/// Runs on `TimelineView`, paused whenever the rope has settled, so an idle Studio
/// window costs nothing. Under Reduce Motion the rope hangs still.
struct StudioRopePreview: View {
    let charm: CustomCharm?
    let reducesMotion: Bool

    @State private var driver = PreviewRopeDriver()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: driver.isPaused)) { context in
                RopeCanvasView(
                    snapshot: driver.snapshot,
                    charmLayers: driver.layers,
                )
                .onChange(of: context.date) { _, date in
                    driver.tick(at: date)
                }
            }
            .background(Color(white: 0.13))
            .onAppear { driver.configure(size: proxy.size, charm: charm, reducesMotion: reducesMotion) }
            .onChange(of: proxy.size) { _, size in driver.resize(to: size) }
            .onChange(of: charm?.metrics) { _, _ in driver.setCharm(charm) }
            .onChange(of: charm?.bitmap.width) { _, _ in driver.setCharm(charm) }
            .onChange(of: reducesMotion) { _, value in driver.setReducesMotion(value) }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    driver.swing()
                } label: {
                    Label("Swing", systemImage: "arrow.left.arrow.right")
                }
                .controlSize(.small)
                .padding(8)
                .disabled(charm == nil || reducesMotion)
                .help("Give the rope a push")
            }
        }
        .accessibilityLabel("Rope preview")
    }
}

/// Owns the preview's simulation and turns it into frames.
@MainActor
@Observable
final class PreviewRopeDriver {
    private(set) var snapshot: RopeSnapshot = .empty
    private(set) var layers: [CharmLayer] = []
    private(set) var isPaused = true

    @ObservationIgnored private let simulation = RopeSimulation()
    @ObservationIgnored private var lastDate: Date?
    @ObservationIgnored private var reducesMotion = false

    func configure(size: CGSize, charm: CustomCharm?, reducesMotion: Bool) {
        self.reducesMotion = reducesMotion
        simulation.resize(to: size)
        simulation.start()
        setCharm(charm)
        if reducesMotion { simulation.resetToHanging() }
        publish()
    }

    func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        simulation.resize(to: size)
        publish()
        isPaused = reducesMotion
    }

    func setCharm(_ charm: CustomCharm?) {
        guard let charm else {
            layers = []
            return
        }
        simulation.setCharmMetrics(charm.metrics)
        layers = [CharmLayer(charm: charm, opacity: 1, scale: 1)]
        publish()
        isPaused = reducesMotion
    }

    func setReducesMotion(_ value: Bool) {
        reducesMotion = value
        if value {
            simulation.resetToHanging()
            publish()
            isPaused = true
        }
    }

    /// A push, so the user can see how the charm's weight moves.
    func swing() {
        guard !reducesMotion else { return }
        simulation.reset()
        lastDate = nil
        publish()
        isPaused = false
    }

    func tick(at date: Date) {
        defer { lastDate = date }
        guard let last = lastDate else { return }
        let delta = date.timeIntervalSince(last)
        guard delta > 0, delta < 0.25 else { return }
        simulation.step(deltaTime: delta)
        publish()
        if simulation.isSleeping {
            isPaused = true
            lastDate = nil
        }
    }

    private func publish() {
        snapshot = simulation.snapshot()
    }
}
