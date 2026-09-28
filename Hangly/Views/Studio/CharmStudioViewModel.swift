//
//  CharmStudioViewModel.swift
//  Hangly
//
//  Presentation state and the undo history for the AI Charm Studio.
//

import CoreGraphics
import Foundation
import Observation
import OSLog

/// Backs the Studio window.
///
/// The pipeline is held as its stages — source, detection, isolated image, draft —
/// so an adjustment re-runs only what it touches: changing the background method
/// re-isolates, moving a slider only re-fits. Vision runs once per source.
///
/// Adjustments are a value with an undo stack. Discrete changes record a step each;
/// a slider drag records one step for the whole drag, via `beginEditing` and
/// `endEditing`. Reprocessing is debounced and generation-checked, so a stale
/// result from a superseded adjustment can never land in the preview.
@MainActor
@Observable
final class CharmStudioViewModel {
    enum Stage: Equatable {
        case empty
        case loading
        case ready
        case saving
        case saved
    }

    private(set) var stage: Stage = .empty
    private(set) var sourceURL: URL?
    private(set) var sourceImage: CGImage?
    private(set) var detection: SubjectDetection = .none
    private(set) var isolated: CGImage?
    private(set) var draft: StudioCharmDraft?
    private(set) var adjustments = StudioAdjustments()
    private(set) var isProcessing = false
    private(set) var errorMessage: String?
    private(set) var savedEntry: CustomCharmEntry?
    private(set) var undoStack = UndoStack<StudioAdjustments>()

    /// Whether saving also puts the charm on the rope.
    var useOnRopeAfterSave = true

    /// Set by the window host so "Done" can close the window.
    @ObservationIgnored var onRequestClose: (@MainActor () -> Void)?

    @ObservationIgnored private let charmManager: CharmManager
    @ObservationIgnored private let accessibility: AccessibilityPreferences
    @ObservationIgnored private var editingSnapshot: StudioAdjustments?
    @ObservationIgnored private var isolatedFor: SubjectRemoval?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let previewID = UUID()

    /// Slider moves within this window collapse into one reprocess.
    private static let debounce: Duration = .milliseconds(60)

    init(charmManager: CharmManager, accessibility: AccessibilityPreferences) {
        self.charmManager = charmManager
        self.accessibility = accessibility
    }

    // MARK: - Derived

    var hasImage: Bool { sourceImage != nil }
    var reducesMotion: Bool { accessibility.reducesMotion }
    var canUndo: Bool { undoStack.canUndo }
    var canRedo: Bool { undoStack.canRedo }

    var canSave: Bool {
        stage == .ready && draft != nil && !isProcessing
    }

    /// The name that will be saved: the field, or a name derived from the file.
    var effectiveName: String {
        let trimmed = adjustments.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let sourceURL { return CharmStudioPipeline.suggestedName(for: sourceURL) }
        return "Custom Charm"
    }

    var subjectSummary: String {
        guard hasImage else { return "" }
        switch detection.instanceCount {
        case 0: return "No subject detected"
        case 1: return "1 subject detected"
        default: return "\(detection.instanceCount) subjects detected"
        }
    }

    /// The draft as a charm, for the lit preview and the rope preview.
    var previewCharm: CustomCharm? {
        guard let draft else { return nil }
        let entry = CustomCharmEntry(
            id: previewID,
            name: effectiveName,
            createdAt: .distantPast,
            imageFileName: "",
            metrics: draft.metrics,
            palette: draft.palette
        )
        return CustomCharm(entry: entry, bitmap: draft.square)
    }

    // MARK: - Loading

    func open(url: URL) async {
        guard CharmImageProcessor.isSupported(url) else {
            errorMessage = CharmImageError.unsupportedType(url.lastPathComponent).localizedDescription
            return
        }

        processingTask?.cancel()
        generation += 1
        stage = .loading
        errorMessage = nil
        savedEntry = nil
        draft = nil
        isolated = nil
        isolatedFor = nil
        sourceURL = url

        do {
            let image = try await CharmStudioPipeline.load(fileAt: url)
            sourceImage = image
            detection = await CharmStudioPipeline.detectSubjects(in: image)
            adjustments = StudioAdjustments(name: CharmStudioPipeline.suggestedName(for: url))
            undoStack.clear()
            editingSnapshot = nil
            stage = .ready
            await reprocessNow()
            let summary = subjectSummary
            let file = url.lastPathComponent
            Logger.overlay.diagnostic("Studio opened \(file); \(summary).")
        } catch {
            stage = .empty
            sourceImage = nil
            sourceURL = nil
            errorMessage = error.localizedDescription
            Logger.overlay.error("Studio could not open image: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Back to the empty state, ready for another image.
    func clear() {
        processingTask?.cancel()
        generation += 1
        stage = .empty
        sourceURL = nil
        sourceImage = nil
        detection = .none
        isolated = nil
        isolatedFor = nil
        draft = nil
        adjustments = StudioAdjustments()
        undoStack.clear()
        editingSnapshot = nil
        errorMessage = nil
        savedEntry = nil
        isProcessing = false
    }

    // MARK: - Adjusting

    /// Applies a change. Records an undo step unless the caller is mid-drag.
    func apply(_ change: (inout StudioAdjustments) -> Void, recordUndo: Bool = true) {
        var next = adjustments
        change(&next)
        next = next.clamped()
        guard next != adjustments else { return }

        if recordUndo, editingSnapshot == nil {
            undoStack.record(adjustments)
        }
        let affectsImage = next.removal != adjustments.removal
            || next.fill != adjustments.fill
            || next.sizeRatio != adjustments.sizeRatio
            || next.weightScale != adjustments.weightScale
        adjustments = next
        if affectsImage {
            scheduleReprocess()
        }
    }

    /// Marks the start of a continuous edit such as a slider drag.
    func beginEditing() {
        guard editingSnapshot == nil else { return }
        editingSnapshot = adjustments
    }

    /// Ends a continuous edit, recording the whole drag as one undo step.
    func endEditing() {
        guard let snapshot = editingSnapshot else { return }
        editingSnapshot = nil
        if snapshot != adjustments {
            undoStack.record(snapshot)
        }
    }

    func undo() {
        endEditing()
        guard let previous = undoStack.undo(current: adjustments) else { return }
        adjustments = previous
        scheduleReprocess()
    }

    func redo() {
        endEditing()
        guard let next = undoStack.redo(current: adjustments) else { return }
        adjustments = next
        scheduleReprocess()
    }

    // MARK: - Processing

    private func scheduleReprocess() {
        processingTask?.cancel()
        processingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            await self.reprocessNow()
        }
    }

    /// Waits for any pending reprocess. Used before saving and by tests.
    func flush() async {
        await processingTask?.value
    }

    private func reprocessNow() async {
        guard let source = sourceImage else { return }
        generation += 1
        let myGeneration = generation
        let current = adjustments
        isProcessing = true
        defer {
            if myGeneration == generation { isProcessing = false }
        }

        do {
            let base: CGImage
            if let isolated, isolatedFor == current.removal {
                base = isolated
            } else {
                base = try await CharmStudioPipeline.isolate(
                    source: source,
                    detection: detection,
                    removal: current.removal
                )
                guard myGeneration == generation else { return }
                isolated = base
                isolatedFor = current.removal
            }

            let built = try await CharmStudioPipeline.buildDraft(from: base, adjustments: current)
            guard myGeneration == generation else { return }
            draft = built
            errorMessage = nil
        } catch {
            guard myGeneration == generation else { return }
            draft = nil
            isolated = nil
            isolatedFor = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Saving

    func save() async {
        await flush()
        guard canSave, let draft else { return }
        stage = .saving

        do {
            let processed = try CharmStudioPipeline.processed(from: draft)
            let entry = try charmManager.saveImport(processed, name: effectiveName, select: useOnRopeAfterSave)
            savedEntry = entry
            stage = .saved
            Logger.overlay.diagnostic("Studio saved charm \(entry.name).")
        } catch {
            errorMessage = error.localizedDescription
            stage = .ready
            Logger.overlay.error("Studio save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func done() {
        onRequestClose?()
        clear()
    }
}
