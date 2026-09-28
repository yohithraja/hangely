//
//  AppEnvironment.swift
//  Hangly
//
//  Composition root: builds the object graph and owns service lifetimes.
//

import Foundation
import OSLog

/// The application's dependency container.
///
/// Services are constructed once, here, and handed to view models through their
/// initialisers. There are no singletons anywhere in Hangly, which is what lets a
/// test build an `AppEnvironment` with a throwaway `UserDefaults` suite and a fake
/// login-item manager and exercise the real view models.
///
/// Ownership is deliberately flat: this object outlives every view, and views own
/// only their view models.
@MainActor
final class AppEnvironment {
    let settingsStore: SettingsStore
    let launchAtLogin: any LaunchAtLoginManaging
    let screenObserver: ScreenObserver
    let overlayController: OverlayWindowController
    let settingsPresenter: SettingsWindowPresenter
    let charmManager: CharmManager
    let customCharmStore: CustomCharmStore
    let charmImportCoordinator: CharmImportCoordinator
    let charmLibrary: CharmLibrary
    let charmLibraryPresenter: CharmLibraryPresenter
    let audio: AudioService
    let accessibility: AccessibilityPreferences
    let charmStudioViewModel: CharmStudioViewModel
    let charmStudioWindowController: CharmStudioWindowController

    /// The menu bar item exists for the whole life of the app, so its view model is
    /// owned here. The Settings window comes and goes, so `makeSettingsViewModel()`
    /// hands ownership of that one to the view instead.
    let menuBarViewModel: MenuBarViewModel

    init(
        settingsStore: SettingsStore = SettingsStore(),
        launchAtLogin: any LaunchAtLoginManaging = LaunchAtLoginService(),
        screenObserver: ScreenObserver = ScreenObserver(),
        customCharmStore: CustomCharmStore = CustomCharmStore(),
        charmLibrary: CharmLibrary = CharmLibrary.bundled()
    ) {
        self.settingsStore = settingsStore
        self.launchAtLogin = launchAtLogin
        self.screenObserver = screenObserver
        let settingsPresenter = SettingsWindowPresenter()
        let charmManager = CharmManager(settingsStore: settingsStore, customStore: customCharmStore)
        let accessibility = AccessibilityPreferences()
        let audio = AudioService(settingsStore: settingsStore)
        let studioViewModel = CharmStudioViewModel(charmManager: charmManager, accessibility: accessibility)
        let studioWindow = CharmStudioWindowController(viewModel: studioViewModel)
        let importCoordinator = CharmImportCoordinator(
            charmManager: charmManager,
            dialogs: CharmDialogs(),
            studio: studioWindow
        )
        let libraryPresenter = CharmLibraryPresenter()
        self.settingsPresenter = settingsPresenter
        self.charmManager = charmManager
        self.customCharmStore = customCharmStore
        self.charmImportCoordinator = importCoordinator
        self.charmLibrary = charmLibrary
        self.charmLibraryPresenter = libraryPresenter
        self.audio = audio
        self.accessibility = accessibility
        self.charmStudioViewModel = studioViewModel
        self.charmStudioWindowController = studioWindow
        self.menuBarViewModel = MenuBarViewModel(
            settingsStore: settingsStore,
            settingsPresenter: settingsPresenter,
            charmManager: charmManager,
            importCoordinator: importCoordinator,
            libraryPresenter: libraryPresenter
        )
        self.overlayController = OverlayWindowController(
            settingsStore: settingsStore,
            screenObserver: screenObserver,
            charmManager: charmManager,
            importCoordinator: importCoordinator,
            audio: audio,
            accessibility: accessibility
        )
    }

    /// Builds a Settings view model. Called by `SettingsView`, which owns the result
    /// for as long as the window is open.
    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(settingsStore: settingsStore, launchAtLogin: launchAtLogin)
    }

    /// Builds a Library view model. Owned by `CharmLibraryView` while it is open.
    func makeCharmLibraryViewModel() -> CharmLibraryViewModel {
        CharmLibraryViewModel(
            library: charmLibrary,
            charmManager: charmManager,
            importCoordinator: charmImportCoordinator
        )
    }

    /// Starts long-lived services. Called once, from `applicationDidFinishLaunching`.
    func bootstrap() {
        reconcileLaunchAtLogin()
        #if !HANGLY_PRODUCTION
        // Also the only thing at launch that touches the whole charm registry, and
        // so the only thing that pays to load every SVG before the overlay appears.
        reportMissingArtwork()
        #endif
        accessibility.start()
        overlayController.start()
        Logger.app.diagnostic("\(AppConstants.appName) bootstrapped.")
    }

    /// Releases window-server and notification resources at termination.
    func shutdown() {
        overlayController.stop()
        audio.stop()
        accessibility.stop()
        Logger.app.diagnostic("\(AppConstants.appName) shut down.")
    }

    /// A collection charm without its SVG draws a placeholder bead rather than
    /// nothing; say so in the log, once, so the omission is never silent.
    #if !HANGLY_PRODUCTION
    private func reportMissingArtwork() {
        let missing = BuiltInCharms.missingArtwork
        guard !missing.isEmpty else { return }
        let names = missing.map(\.rawValue).joined(separator: ", ")
        Logger.overlay.error("Missing SVG artwork for: \(names, privacy: .public)")
    }
    #endif

    /// The login-item registry is the source of truth — a user can remove the item in
    /// System Settings without Hangly running. Trusting the persisted flag instead
    /// would leave the Settings toggle showing a state that is no longer real.
    /// Brings the login item and the stored preference into agreement.
    ///
    /// `LaunchAtLoginPolicy` decides which of the two wins; this applies the answer.
    /// A first run also writes the document out even when nothing changed, so the
    /// next launch knows it is not a first run and leaves the user's choice alone.
    private func reconcileLaunchAtLogin() {
        let decision = LaunchAtLoginPolicy.decide(
            isFirstRun: settingsStore.isFirstRun,
            stored: settingsStore.settings.launchAtLogin,
            registered: launchAtLogin.isEnabled
        )

        switch decision {
        case .doNothing:
            break

        case .register:
            do {
                try launchAtLogin.setEnabled(true)
                Logger.settings.diagnostic("Registered the login item on first run.")
            } catch {
                // Registration is refused for a build without a stable signing
                // identity, or one running from a location the system will not vouch
                // for. During development that is normal rather than a failure worth
                // interrupting anyone over, so the preference is corrected to match
                // what actually happened and Settings shows the real state.
                Logger.settings.warning(
                    "Could not register the login item: \(error.localizedDescription, privacy: .public)"
                )
                settingsStore.update { $0.launchAtLogin = false }
            }

        case .follow(let registered):
            Logger.settings.diagnostic("Reconciling launch-at-login to \(registered).")
            settingsStore.update { $0.launchAtLogin = registered }
        }

        if settingsStore.isFirstRun {
            settingsStore.save()
        }
    }
}
