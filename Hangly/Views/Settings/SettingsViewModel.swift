//
//  SettingsViewModel.swift
//  Hangly
//
//  Presentation state for the Settings window.
//

import Foundation
import Observation
import OSLog

/// Backs every tab of the Settings window.
///
/// The properties below are deliberately flat proxies onto `SettingsStore`: reads go
/// straight through (so Observation tracks them and the UI stays live) and writes go
/// through `update`, which persists atomically. The view therefore never sees
/// `AppSettings`, only the individual values it renders.
@MainActor
@Observable
final class SettingsViewModel {
    /// Set when `SMAppService` refuses a change, e.g. for an unsigned debug build.
    /// Surfaced inline rather than as an alert so the toggle and the reason stay together.
    var launchAtLoginError: String?

    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let launchAtLogin: any LaunchAtLoginManaging

    init(settingsStore: SettingsStore, launchAtLogin: any LaunchAtLoginManaging) {
        self.settingsStore = settingsStore
        self.launchAtLogin = launchAtLogin
    }

    // MARK: - General

    var isOverlayVisible: Bool {
        get { settingsStore.settings.overlay.isEnabled }
        set { settingsStore.update { $0.overlay.isEnabled = newValue } }
    }

    var launchesAtLogin: Bool {
        get { settingsStore.settings.launchAtLogin }
        set { applyLaunchAtLogin(newValue) }
    }

    // MARK: - Sound

    var soundEffectsEnabled: Bool {
        get { settingsStore.settings.soundEffectsEnabled }
        set { settingsStore.update { $0.soundEffectsEnabled = newValue } }
    }

    var soundVolume: Double {
        get { settingsStore.settings.soundVolume }
        set { settingsStore.update { $0.soundVolume = newValue.clamped(to: AppSettings.soundVolumeRange) } }
    }

    var soundVolumeRange: ClosedRange<Double> { AppSettings.soundVolumeRange }
    var soundVolumeDescription: String { percentString(soundVolume) }

    // MARK: - Overlay

    var anchor: OverlayAnchor {
        get { settingsStore.settings.overlay.anchor }
        set { settingsStore.update { $0.overlay.anchor = newValue } }
    }

    var scale: Double {
        get { settingsStore.settings.overlay.scale }
        set { settingsStore.update { $0.overlay.scale = newValue.clamped(to: scaleRange) } }
    }

    var opacity: Double {
        get { settingsStore.settings.overlay.opacity }
        set { settingsStore.update { $0.overlay.opacity = newValue.clamped(to: opacityRange) } }
    }

    var horizontalOffset: Double {
        get { settingsStore.settings.overlay.horizontalOffset }
        set { settingsStore.update { $0.overlay.horizontalOffset = newValue.clamped(to: horizontalOffsetRange) } }
    }

    var verticalOffset: Double {
        get { settingsStore.settings.overlay.verticalOffset }
        set { settingsStore.update { $0.overlay.verticalOffset = newValue.clamped(to: verticalOffsetRange) } }
    }

    var isClickThrough: Bool {
        get { settingsStore.settings.overlay.isClickThrough }
        set { settingsStore.update { $0.overlay.isClickThrough = newValue } }
    }

    var joinsAllSpaces: Bool {
        get { settingsStore.settings.overlay.joinsAllSpaces }
        set { settingsStore.update { $0.overlay.joinsAllSpaces = newValue } }
    }

    var anchorsToScreenEdge: Bool {
        get { settingsStore.settings.overlay.anchorsToScreenEdge }
        set { settingsStore.update { $0.overlay.anchorsToScreenEdge = newValue } }
    }

    // MARK: - Ranges for the UI

    var scaleRange: ClosedRange<Double> { OverlaySettings.Limits.scale }
    var opacityRange: ClosedRange<Double> { OverlaySettings.Limits.opacity }
    var horizontalOffsetRange: ClosedRange<Double> { OverlaySettings.Limits.horizontalOffset }
    var verticalOffsetRange: ClosedRange<Double> { OverlaySettings.Limits.verticalOffset }

    // MARK: - Formatted values

    var scaleDescription: String { percentString(scale) }
    var opacityDescription: String { percentString(opacity) }
    var horizontalOffsetDescription: String { pointString(horizontalOffset) }
    var verticalOffsetDescription: String { pointString(verticalOffset) }

    // MARK: - About

    var appName: String { AppConstants.appName }
    var versionDescription: String { "Version \(AppConstants.shortVersion) (\(AppConstants.buildNumber))" }
    var copyright: String { AppConstants.copyright }

    // MARK: - Commands

    /// Restores overlay appearance and placement, leaving startup preferences alone.
    func resetOverlaySettings() {
        settingsStore.update { settings in
            let wasEnabled = settings.overlay.isEnabled
            settings.overlay = OverlaySettings()
            settings.overlay.isEnabled = wasEnabled
        }
    }

    /// Restores every preference, including the login item — which means restoring
    /// it to the shipped default rather than to off, so a reset leaves the app in
    /// the state a fresh install would be in.
    func resetAllSettings() {
        settingsStore.resetToDefaults()
        applyLaunchAtLogin(settingsStore.settings.launchAtLogin)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
            settingsStore.update { $0.launchAtLogin = enabled }
        } catch {
            // Re-read the registry so the toggle snaps back to reality instead of
            // showing a state the system rejected.
            Logger.settings.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            launchAtLoginError = error.localizedDescription
            settingsStore.update { $0.launchAtLogin = launchAtLogin.isEnabled }
        }
    }

    private func percentString(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func pointString(_ value: Double) -> String {
        "\(Int(value.rounded())) pt"
    }
}
