//
//  MenuBarView.swift
//  Hangly
//
//  Contents of the menu bar dropdown.
//

import SwiftUI

/// The menu shown when the status item is clicked.
///
/// Rendered with `.menu` style, so SwiftUI converts this tree into a real `NSMenu`.
/// That buys native appearance, keyboard navigation and VoiceOver support for free,
/// and is why the menu holds only commands — the richer controls live in Settings.
struct MenuBarView: View {
    @Environment(\.openSettings)
    private var openSettings

    @Environment(\.openWindow)
    private var openWindow

    /// Owned by `AppEnvironment`: the status item and its menu share one view model,
    /// so the icon and the checkmark can never disagree.
    let viewModel: MenuBarViewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Toggle("Show Overlay", isOn: $viewModel.isOverlayVisible)
            .keyboardShortcut("o", modifiers: [.command, .shift])

        // An inline picker inside a submenu is what AppKit renders as a checkmarked
        // group, which is the native way to present a single choice in a menu.
        Menu("Charm") {
            Picker("Charm", selection: $viewModel.charmID) {
                ForEach(viewModel.charmMenuItems) { item in
                    Label(item.name, systemImage: item.symbolName)
                        .tag(item.id)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button("Charm Library…") {
                viewModel.showCharmLibrary(using: openWindow)
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("AI Charm Studio…") {
                viewModel.openCharmStudio()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(viewModel.isImportingCharm ? "Importing…" : "Import Image…") {
                viewModel.importCharmImage()
            }
            .disabled(viewModel.isImportingCharm)

            Button("Delete Current Charm…") {
                viewModel.deleteCurrentCharm()
            }
            .disabled(!viewModel.canDeleteCurrentCharm)
        }

        Divider()

        Button("Settings…") {
            viewModel.showSettings(using: openSettings)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit \(AppConstants.appName)") {
            viewModel.quit()
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
