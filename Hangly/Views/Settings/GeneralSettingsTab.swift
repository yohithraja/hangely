//
//  GeneralSettingsTab.swift
//  Hangly
//

import SwiftUI

/// Startup and app-wide preferences.
struct GeneralSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Show overlay", isOn: $viewModel.isOverlayVisible)
            } header: {
                Text("Overlay")
            } footer: {
                Text("The overlay floats above other apps and ignores clicks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Play sound effects", isOn: $viewModel.soundEffectsEnabled)

                SliderRow(
                    title: "Volume",
                    valueDescription: viewModel.soundVolumeDescription,
                    range: viewModel.soundVolumeRange,
                    value: $viewModel.soundVolume
                )
                .disabled(!viewModel.soundEffectsEnabled)
            } header: {
                Text("Sound")
            } footer: {
                Text("Charms sound when you swing or switch them. Bells ring; wood and clay knock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch Hangly at login", isOn: $viewModel.launchesAtLogin)

                if let error = viewModel.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Hangly runs in the menu bar and has no Dock icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings…", role: .destructive) {
                    isConfirmingReset = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                viewModel.resetAllSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Overlay appearance, placement and startup preferences return to their defaults.")
        }
    }
}
