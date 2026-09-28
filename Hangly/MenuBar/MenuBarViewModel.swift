//
//  MenuBarViewModel.swift
//  Hangly
//
//  Presentation state and commands for the menu bar item.
//

import AppKit
import Observation
import OSLog
import SwiftUI

/// Backs `MenuBarView`.
///
/// The view model owns the only two decisions the menu can make — toggle the overlay
/// and open Settings — plus quitting. Keeping `NSApp` here means the menu itself
/// stays pure SwiftUI.
@MainActor
@Observable
final class MenuBarViewModel {
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let settingsPresenter: SettingsWindowPresenter
    @ObservationIgnored private let charmManager: CharmManager
    @ObservationIgnored private let importCoordinator: CharmImportCoordinator
    @ObservationIgnored private let libraryPresenter: CharmLibraryPresenter

    init(
        settingsStore: SettingsStore,
        settingsPresenter: SettingsWindowPresenter,
        charmManager: CharmManager,
        importCoordinator: CharmImportCoordinator,
        libraryPresenter: CharmLibraryPresenter
    ) {
        self.settingsStore = settingsStore
        self.settingsPresenter = settingsPresenter
        self.charmManager = charmManager
        self.importCoordinator = importCoordinator
        self.libraryPresenter = libraryPresenter
    }

    /// Opens the Charm Library window and brings it to the front.
    func showCharmLibrary(using openWindow: OpenWindowAction) {
        libraryPresenter.present(using: openWindow)
    }

    /// Charms offered in the menu: the built-ins, then every import. Observable, so
    /// the menu grows the moment an import lands.
    var charmMenuItems: [CharmMenuItem] {
        charmManager.menuItems
    }

    /// The charm on the rope. Changing it takes effect on the next frame; there is
    /// nothing to confirm and nothing to restart.
    var charmID: CharmID {
        get { charmManager.selection }
        set { charmManager.selection = newValue }
    }

    var isImportingCharm: Bool {
        charmManager.isImporting
    }

    /// Only imports can be deleted.
    var canDeleteCurrentCharm: Bool {
        charmManager.canDeleteCurrent
    }

    func importCharmImage() {
        importCoordinator.importFromOpenPanel()
    }

    func openCharmStudio() {
        importCoordinator.openStudio()
    }

    func deleteCurrentCharm() {
        importCoordinator.deleteCurrentCharm()
    }

    /// Bound to the menu's checkmark item.
    var isOverlayVisible: Bool {
        get { settingsStore.settings.overlay.isEnabled }
        set {
            settingsStore.update { $0.overlay.isEnabled = newValue }
            Logger.menuBar.diagnostic("Overlay visibility set to \(newValue).")
        }
    }

    /// Opens the Settings window and brings it to the front.
    /// - Parameter openSettings: SwiftUI environment action, readable only in a view.
    func showSettings(using openSettings: OpenSettingsAction) {
        settingsPresenter.present(using: openSettings)
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
