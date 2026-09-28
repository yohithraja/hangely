//
//  CharmImportCoordinator.swift
//  Hangly
//
//  The one place an import or deletion is started from.
//

import Foundation
import OSLog

/// Routes imports and deletions and reports their outcome to the user.
///
/// Every interactive import — the menu, a drop on the overlay, the Library's
/// toolbar — opens the Studio with the file loaded, so nothing reaches the library
/// without the user having seen it. `importImage(at:)` remains as the direct,
/// unattended path. Unsupported files are refused with a message before any window
/// opens.
@MainActor
final class CharmImportCoordinator {
    private let charmManager: CharmManager
    private let dialogs: CharmDialogs
    private let studio: CharmStudioWindowController
    private var importTask: Task<Void, Never>?

    init(charmManager: CharmManager, dialogs: CharmDialogs, studio: CharmStudioWindowController) {
        self.charmManager = charmManager
        self.dialogs = dialogs
        self.studio = studio
    }

    /// Menu path: ask for a file, then open it in the Studio.
    func importFromOpenPanel() {
        guard let url = dialogs.chooseImage() else { return }
        presentStudio(with: url)
    }

    /// Opens the Studio empty.
    func openStudio() {
        studio.present()
    }

    /// Opens the Studio with `url` loaded.
    /// - Returns: Whether the file was accepted.
    @discardableResult
    func presentStudio(with url: URL?) -> Bool {
        if let url, !CharmImageProcessor.isSupported(url) {
            dialogs.presentError(
                CharmImageError.unsupportedType(url.lastPathComponent),
                title: "Couldn't Open Image"
            )
            return false
        }
        studio.present(url: url)
        return true
    }

    /// Imports `url` in the background and selects the result.
    /// - Returns: Whether the import was started.
    @discardableResult
    func importImage(at url: URL) -> Bool {
        guard CharmImageProcessor.isSupported(url) else {
            dialogs.presentError(
                CharmImageError.unsupportedType(url.lastPathComponent),
                title: "Couldn't Import Image"
            )
            return false
        }
        guard !charmManager.isImporting else {
            Logger.overlay.diagnostic("Ignoring import while another is in progress.")
            return false
        }

        let name = Self.charmName(for: url)
        importTask = Task { @MainActor [charmManager, dialogs] in
            do {
                try await charmManager.importImage(at: url, name: name)
            } catch {
                Logger.overlay.error("Import failed: \(error.localizedDescription, privacy: .public)")
                dialogs.presentError(error, title: "Couldn't Import Image")
            }
        }
        return true
    }

    /// Deletes the selected charm after confirmation. Does nothing for a built-in.
    func deleteCurrentCharm() {
        guard case .custom(let id) = charmManager.selection,
              let entry = charmManager.customEntry(for: id) else { return }
        guard dialogs.confirmDelete(named: entry.name) else { return }

        do {
            try charmManager.deleteCharm(id: id)
        } catch {
            Logger.overlay.error("Delete failed: \(error.localizedDescription, privacy: .public)")
            dialogs.presentError(error, title: "Couldn't Delete Charm")
        }
    }

    /// The file name without its extension, tidied. "IMG_0421" is still better than
    /// nothing, and the user never has to type a name to get a charm.
    private static func charmName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Custom Charm" : stem
    }
}
