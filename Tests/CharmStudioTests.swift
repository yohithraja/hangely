//
//  CharmStudioTests.swift
//  HanglyTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Hangly

/// The Studio's pipeline stages on synthetic images with known answers.
@Suite("Studio pipeline")
struct CharmStudioPipelineTests {
    private func fixture(_ image: CGImage, as type: UTType, name: String) throws -> URL {
        let url = try TestImages.temporaryDirectory().appending(path: name)
        try TestImages.write(image, as: type, to: url)
        return url
    }

    @Test("HEIC is supported by name and decodes")
    func heicLoads() throws {
        #expect(CharmImageProcessor.isSupported(URL(fileURLWithPath: "/tmp/a.heic")))
        #expect(CharmImageProcessor.isSupported(URL(fileURLWithPath: "/tmp/a.HEIF")))

        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        guard writable.contains(UTType.heic.identifier) else { return }

        let disc = try #require(TestImages.discOnWhite())
        let url = try fixture(disc, as: .heic, name: "disc.heic")
        let loaded = try CharmImageProcessor.load(fileAt: url)
        #expect(loaded.width == 256)
    }

    @Test("Subject detection finds the disc and keeps a cut-out per instance")
    func detectsSubjects() async throws {
        let disc = try #require(TestImages.discOnWhite())
        let detection = await CharmStudioPipeline.detectSubjects(in: disc)

        #expect(detection.hasSubject)
        #expect(detection.cutouts.count == detection.instanceCount + 1)
        #expect(detection.cutout(instance: nil) != nil)
        #expect(detection.cutout(instance: 1) != nil)
        #expect(detection.cutout(instance: 99) == nil)
    }

    @Test("Each removal method behaves as described")
    func removalMethods() async throws {
        let onWhite = try #require(TestImages.discOnWhite())
        let onClear = try #require(TestImages.discOnClear())
        let detection = await CharmStudioPipeline.detectSubjects(in: onWhite)

        let kept = try await CharmStudioPipeline.isolate(source: onWhite, detection: detection, removal: .keepOriginal)
        #expect(kept.width == onWhite.width)
        #expect(RGBABitmap(image: kept)?.alpha(x: 2, y: 2) == 255)

        let flat = try await CharmStudioPipeline.isolate(
            source: onWhite, detection: detection, removal: .flatBackground(tolerance: 36)
        )
        #expect(RGBABitmap(image: flat)?.alpha(x: 2, y: 2) == 0)
        #expect(RGBABitmap(image: flat)?.alpha(x: 128, y: 128) == 255)

        let subject = try await CharmStudioPipeline.isolate(
            source: onWhite, detection: detection, removal: .detectedSubject(instance: nil)
        )
        #expect(subject.width > 0)

        // Existing transparency is trusted by the automatic method.
        let auto = try await CharmStudioPipeline.isolate(source: onClear, detection: .none, removal: .automatic)
        #expect(auto.width == onClear.width)

        await #expect(throws: CharmImageError.noSubjectDetected) {
            try await CharmStudioPipeline.isolate(
                source: onWhite, detection: .none, removal: .detectedSubject(instance: nil)
            )
        }
    }

    @Test("A draft applies the user's size, weight and fill")
    func draftAppliesAdjustments() async throws {
        let cut = try #require(TestImages.discOnClear())
        var adjustments = StudioAdjustments()
        adjustments.sizeRatio = 0.15
        adjustments.weightScale = 2
        adjustments.fill = 0.75

        let draft = try await CharmStudioPipeline.buildDraft(from: cut, adjustments: adjustments)
        let bitmap = try #require(RGBABitmap(image: draft.square))
        let bounds = try #require(bitmap.opaqueBounds(threshold: 8))

        #expect(draft.metrics.radiusRatio == 0.15)
        #expect(abs(draft.metrics.mass - (draft.analysedMass * 2)) < 1e-9)
        #expect(abs(Double(bounds.width) - (512 * 0.75)) < 4)

        let processed = try CharmStudioPipeline.processed(from: draft)
        #expect(processed.pixelSide == 512)
        #expect(!processed.pngData.isEmpty)
    }

    @Test("Adjustments clamp into their ranges")
    func adjustmentsClamp() {
        var wild = StudioAdjustments()
        wild.sizeRatio = 9
        wild.weightScale = 0
        wild.fill = 2
        wild.removal = .flatBackground(tolerance: 1000)

        let clamped = wild.clamped()
        #expect(clamped.sizeRatio == StudioAdjustments.sizeRange.upperBound)
        #expect(clamped.weightScale == StudioAdjustments.weightRange.lowerBound)
        #expect(clamped.fill == StudioAdjustments.fillRange.upperBound)
        #expect(clamped.removal == .flatBackground(tolerance: StudioAdjustments.toleranceRange.upperBound))
    }

    @Test("Names come from the file, tidied")
    func suggestedNames() {
        #expect(CharmStudioPipeline.suggestedName(for: URL(fileURLWithPath: "/x/my_lucky-cat.png")) == "my lucky cat")
        #expect(CharmStudioPipeline.suggestedName(for: URL(fileURLWithPath: "/x/.png")) == "Custom Charm")
    }
}

@Suite("Undo stack")
struct UndoStackTests {
    @Test("Undo and redo walk the history and a new change drops the redo branch")
    func walksHistory() {
        var stack = UndoStack<Int>()
        var value = 1

        stack.record(value); value = 2
        stack.record(value); value = 3
        #expect(stack.canUndo)
        #expect(!stack.canRedo)

        value = stack.undo(current: value) ?? value
        #expect(value == 2)
        value = stack.undo(current: value) ?? value
        #expect(value == 1)
        #expect(!stack.canUndo)
        #expect(stack.undo(current: value) == nil)

        value = stack.redo(current: value) ?? value
        #expect(value == 2)

        stack.record(value); value = 20
        #expect(!stack.canRedo)
        #expect(stack.redo(current: value) == nil)
        #expect(stack.undo(current: value) == 2)
    }

    @Test("History is capped")
    func capped() {
        var stack = UndoStack<Int>()
        stack.limit = 3
        for step in 0..<10 { stack.record(step) }
        #expect(stack.past == [7, 8, 9])
    }
}

/// The whole workflow through the view model: open, adjust, undo, save.
@Suite("Studio workflow")
@MainActor
struct CharmStudioViewModelTests {
    private struct Fixture {
        let viewModel: CharmStudioViewModel
        let manager: CharmManager
        let store: CustomCharmStore
        let defaults: UserDefaults
        let suiteName: String
        let directory: URL

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "com.hangly.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let directory = try TestImages.temporaryDirectory()
        let store = CustomCharmStore(directory: directory.appending(path: "charms"))
        let manager = CharmManager(
            settingsStore: SettingsStore(defaults: defaults, storageKey: "settings"),
            customStore: store
        )
        let viewModel = CharmStudioViewModel(charmManager: manager, accessibility: AccessibilityPreferences())
        return Fixture(
            viewModel: viewModel,
            manager: manager,
            store: store,
            defaults: defaults,
            suiteName: suiteName,
            directory: directory
        )
    }

    private func discFile(in fixture: Fixture, name: String = "Lucky Disc.png") throws -> URL {
        let disc = try #require(TestImages.discOnWhite())
        let url = fixture.directory.appending(path: name)
        try TestImages.write(disc, as: .png, to: url)
        return url
    }

    @Test("Opening an image yields a draft with a suggested name")
    func opensToReady() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let viewModel = fixture.viewModel

        await viewModel.open(url: try discFile(in: fixture))
        await viewModel.flush()

        #expect(viewModel.stage == .ready)
        #expect(viewModel.draft != nil)
        #expect(viewModel.previewCharm != nil)
        #expect(viewModel.effectiveName == "Lucky Disc")
        #expect(viewModel.canSave)
        #expect(!viewModel.canUndo)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Adjustments change the draft and undo restores it")
    func adjustAndUndo() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let viewModel = fixture.viewModel
        await viewModel.open(url: try discFile(in: fixture))
        await viewModel.flush()
        let original = try #require(viewModel.draft?.metrics.radiusRatio)

        viewModel.apply { $0.sizeRatio = 0.15 }
        await viewModel.flush()
        #expect(viewModel.draft?.metrics.radiusRatio == 0.15)
        #expect(viewModel.canUndo)

        viewModel.undo()
        await viewModel.flush()
        #expect(viewModel.draft?.metrics.radiusRatio == original)
        #expect(viewModel.canRedo)

        viewModel.redo()
        await viewModel.flush()
        #expect(viewModel.draft?.metrics.radiusRatio == 0.15)
    }

    @Test("A slider drag is one undo step, not one per tick")
    func dragIsOneStep() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let viewModel = fixture.viewModel
        await viewModel.open(url: try discFile(in: fixture))
        await viewModel.flush()

        viewModel.beginEditing()
        for value in stride(from: 1.0, through: 1.8, by: 0.1) {
            viewModel.apply({ $0.weightScale = value }, recordUndo: false)
        }
        viewModel.endEditing()
        await viewModel.flush()

        #expect(viewModel.undoStack.past.count == 1)
        #expect(abs(viewModel.adjustments.weightScale - 1.8) < 1e-9)

        viewModel.undo()
        #expect(abs(viewModel.adjustments.weightScale - 1.0) < 1e-9)
        #expect(!viewModel.canUndo)
    }

    @Test("Changing the method re-isolates, and an impossible method reports rather than crashes")
    func methodChanges() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let viewModel = fixture.viewModel
        await viewModel.open(url: try discFile(in: fixture))
        await viewModel.flush()

        viewModel.apply { $0.removal = .keepOriginal }
        await viewModel.flush()
        #expect(viewModel.isolated?.width == 256)
        #expect(RGBABitmap(image: try #require(viewModel.isolated))?.alpha(x: 2, y: 2) == 255)

        viewModel.apply { $0.removal = .detectedSubject(instance: 99) }
        await viewModel.flush()
        #expect(viewModel.draft == nil)
        #expect(viewModel.errorMessage == CharmImageError.noSubjectDetected.localizedDescription)
        #expect(!viewModel.canSave)

        viewModel.undo()
        await viewModel.flush()
        #expect(viewModel.draft != nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Saving stores the charm, names it, and puts it on the rope when asked")
    func saves() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let viewModel = fixture.viewModel
        await viewModel.open(url: try discFile(in: fixture))
        viewModel.apply { $0.name = "  Studio Disc  " }

        await viewModel.save()

        let entry = try #require(fixture.store.entries.first)
        #expect(viewModel.stage == .saved)
        #expect(entry.name == "Studio Disc")
        #expect(fixture.manager.selection == .custom(entry.id))
        #expect(viewModel.savedEntry == entry)

        // Make another: back to empty, library untouched.
        viewModel.clear()
        #expect(viewModel.stage == .empty)
        #expect(fixture.store.entries.count == 1)
    }

    @Test("Saving without selecting leaves the rope alone")
    func savesWithoutSelecting() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let viewModel = fixture.viewModel
        await viewModel.open(url: try discFile(in: fixture))
        viewModel.useOnRopeAfterSave = false

        await viewModel.save()

        #expect(fixture.store.entries.count == 1)
        #expect(fixture.manager.selection == OverlaySettings().charm)
    }

    @Test("Bad input is reported and leaves the Studio empty")
    func rejectsBadInput() async throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let viewModel = fixture.viewModel

        await viewModel.open(url: URL(fileURLWithPath: "/tmp/notes.txt"))
        #expect(viewModel.stage == .empty)
        #expect(viewModel.errorMessage?.contains("not a supported image") == true)

        let broken = fixture.directory.appending(path: "broken.png")
        try Data("garbage".utf8).write(to: broken)
        await viewModel.open(url: broken)
        #expect(viewModel.stage == .empty)
        #expect(viewModel.sourceImage == nil)
        #expect(viewModel.errorMessage == CharmImageError.unreadable.localizedDescription)
        #expect(fixture.store.entries.isEmpty)
    }
}
