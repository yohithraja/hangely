//
//  AboutSettingsTab.swift
//  Hangly
//

import AppKit
import SwiftUI

/// Identity, credit, and a button that knows things.
struct AboutSettingsTab: View {
    let viewModel: SettingsViewModel

    /// Held here rather than in the view model: nothing outside this pane has any
    /// business knowing what the app has admitted to this session.
    @State private var vault = SecretVault()
    @State private var revealed: Secret?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            identity
            Divider().frame(maxWidth: 260)
            survival
            Divider().frame(maxWidth: 260)
            credit
            Divider().frame(maxWidth: 260)
            secrets
            Divider().frame(maxWidth: 260)
            footer
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(spacing: 6) {
            appIcon
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            Text(viewModel.appName)
                .font(.title2.weight(.semibold))

            Text("A tiny piece of motion for your desktop.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var appIcon: some View {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "circle.circle")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.tint)
        }
    }

    // MARK: - Vital statistics, loosely defined

    private var survival: some View {
        VStack(spacing: 3) {
            Text("This rope has survived 4,328,127 swings.")
                .font(.callout)

            Text("Physics simulation: 97%")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Magic: 3%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var credit: some View {
        VStack(spacing: 3) {
            Text("Designed and built by")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("sharancreatedthis")
                .font(.callout.weight(.medium))

            Text("Photography • Film • Design • Code")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Secrets

    private var secrets: some View {
        VStack(spacing: 8) {
            Button("Tell Me a Secret") {
                let next = vault.reveal()
                if reduceMotion {
                    revealed = next
                } else {
                    withAnimation(.easeInOut(duration: 0.28)) { revealed = next }
                }
            }
            .controlSize(.regular)
            .accessibilityLabel("Tell me a secret")
            .accessibilityHint("Reveals one of the app's secrets")

            secretArea
        }
    }

    /// A fixed-height stage, so revealing a secret fades one in rather than pushing
    /// the window's contents around. The `ZStack` is what makes it a crossfade: the
    /// outgoing secret is still there, fading, while the incoming one arrives.
    private var secretArea: some View {
        ZStack {
            if let secret = revealed {
                secretView(secret)
                    .id(secret)
                    .transition(.opacity)
            }
        }
        .frame(height: 46)
        .frame(maxWidth: 340)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(revealed.map(accessibilityDescription) ?? "No secret revealed yet")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private func secretView(_ secret: Secret) -> some View {
        VStack(spacing: 2) {
            if let title = secret.title {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(secret.rarity == .common ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
            }

            Text(secret.message)
                .font(messageFont(for: secret))
                .foregroundStyle(secret.title == nil ? .primary : .secondary)

            if let attribution = secret.attribution {
                Text(attribution)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The luck bar is drawn out of block characters, which only line up into a bar
    /// in a face whose glyphs share an advance. Everything else keeps the app's
    /// regular one.
    private func messageFont(for secret: Secret) -> Font {
        secret.message.contains(where: \.isBlockElement) ? .callout.monospaced() : .callout
    }

    private func accessibilityDescription(_ secret: Secret) -> String {
        [secret.title, secret.message, secret.attribution]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 3) {
            Text(viewModel.versionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Secrets discovered this session: \(vault.revealedCount)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .accessibilityLabel("Secrets discovered this session: \(vault.revealedCount)")

            Text(viewModel.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
