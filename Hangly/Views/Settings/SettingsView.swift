//
//  SettingsView.swift
//  Hangly
//
//  Root of the Settings scene.
//

import SwiftUI

/// The Settings window.
///
/// Owns the `SettingsViewModel` via `@State` so it survives SwiftUI re-evaluating the
/// scene, and builds it from the injected `AppEnvironment` — the same graph the rest
/// of the app uses, with no globals reached for along the way.
///
/// A fixed frame is intentional: a tabbed macOS settings window that resizes itself
/// as the user switches tabs feels broken.
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: environment.makeSettingsViewModel())
    }

    var body: some View {
        TabView {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }

            OverlaySettingsTab(viewModel: viewModel)
                .tabItem { Label("Overlay", systemImage: "macwindow.on.rectangle") }

            AboutSettingsTab(viewModel: viewModel)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}
