//
//  OverlaySettingsTab.swift
//  Hangly
//

import SwiftUI

/// Appearance, placement and behaviour of the floating overlay.
struct OverlaySettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Appearance") {
                SliderRow(
                    title: "Size",
                    valueDescription: viewModel.scaleDescription,
                    range: viewModel.scaleRange,
                    value: $viewModel.scale
                )

                SliderRow(
                    title: "Opacity",
                    valueDescription: viewModel.opacityDescription,
                    range: viewModel.opacityRange,
                    value: $viewModel.opacity
                )
            }

            Section {
                Picker("Position", selection: $viewModel.anchor) {
                    ForEach(OverlayAnchor.allCases) { anchor in
                        Text(anchor.displayName).tag(anchor)
                    }
                }

                SliderRow(
                    title: "Horizontal offset",
                    valueDescription: viewModel.horizontalOffsetDescription,
                    range: viewModel.horizontalOffsetRange,
                    value: $viewModel.horizontalOffset
                )

                SliderRow(
                    title: "Vertical offset",
                    valueDescription: viewModel.verticalOffsetDescription,
                    range: viewModel.verticalOffsetRange,
                    value: $viewModel.verticalOffset
                )

                Toggle("Hang from the screen edge", isOn: $viewModel.anchorsToScreenEdge)
            } header: {
                Text("Placement")
            } footer: {
                Text("Turn this on to anchor above the menu bar instead of below it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Let clicks pass through", isOn: $viewModel.isClickThrough)
                Toggle("Show on all Spaces", isOn: $viewModel.joinsAllSpaces)
            } header: {
                Text("Behaviour")
            } footer: {
                Text("With click-through on, the overlay never intercepts the mouse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset Overlay Settings") {
                    viewModel.resetOverlaySettings()
                }
            }
        }
        .formStyle(.grouped)
    }
}
