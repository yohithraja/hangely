//
//  CharmStudioPipeline.swift
//  Hangly
//
//  The import pipeline as separate, previewable stages.
//

import CoreGraphics
import CoreImage
import Foundation
import Vision

/// What Vision found in a source image.
///
/// Every cut-out is generated up front so the Studio can switch between subjects
/// without touching Vision again: index zero is every instance together, then one
/// entry per instance. Cut-outs are cropped to their own extent.
struct SubjectDetection: Sendable {
    let instanceCount: Int
    let cutouts: [CGImage]

    static let none = SubjectDetection(instanceCount: 0, cutouts: [])

    var hasSubject: Bool { instanceCount > 0 }

    /// - Parameter instance: 1-based instance number, or `nil` for all of them.
    func cutout(instance: Int?) -> CGImage? {
        guard hasSubject else { return nil }
        guard let instance else { return cutouts.first }
        guard instance >= 1, instance < cutouts.count else { return nil }
        return cutouts[instance]
    }
}

/// A charm as the Studio currently has it: the square bitmap plus the numbers.
struct StudioCharmDraft: Sendable {
    let square: CGImage
    let metrics: CharmMetrics
    let palette: CharmPalette

    /// The mass the analysis derived before the user's weight scale was applied.
    let analysedMass: Double
}

/// `CharmImageProcessor` split into stages the Studio can run one at a time.
///
/// The one-shot importer runs load → isolate → fit → analyse → encode in a single
/// task. The Studio needs the same steps as separate calls, so that changing the
/// background method re-runs isolation only, and moving a slider re-runs fitting
/// only. Subject detection is the expensive step and is run once per source.
enum CharmStudioPipeline {
    static func load(fileAt url: URL) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            try CharmImageProcessor.load(fileAt: url)
        }.value
    }

    /// Runs Vision once and keeps every cut-out. Never throws: no subject is a
    /// result, not a failure.
    static func detectSubjects(in image: CGImage) async -> SubjectDetection {
        await Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.first,
                  !observation.allInstances.isEmpty else {
                return .none
            }

            let context = CIContext(options: [.useSoftwareRenderer: false])
            func cutout(_ instances: IndexSet) -> CGImage? {
                guard let buffer = try? observation.generateMaskedImage(
                    ofInstances: instances,
                    from: handler,
                    croppedToInstancesExtent: true
                ) else { return nil }
                let ciImage = CIImage(cvPixelBuffer: buffer)
                return context.createCGImage(ciImage, from: ciImage.extent)
            }

            guard let everything = cutout(observation.allInstances) else { return .none }
            var cutouts = [everything]
            for instance in observation.allInstances {
                if let single = cutout(IndexSet(integer: instance)) {
                    cutouts.append(single)
                }
            }
            return SubjectDetection(instanceCount: observation.allInstances.count, cutouts: cutouts)
        }.value
    }

    /// Applies the chosen background removal.
    static func isolate(
        source: CGImage,
        detection: SubjectDetection,
        removal: SubjectRemoval
    ) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            switch removal {
            case .keepOriginal:
                return source
            case .flatBackground(let tolerance):
                return try CharmImageProcessor.floodFillBackground(of: source, tolerance: tolerance)
            case .detectedSubject(let instance):
                guard let cutout = detection.cutout(instance: instance) else {
                    throw CharmImageError.noSubjectDetected
                }
                return cutout
            case .automatic:
                if CharmImageProcessor.hasMeaningfulAlpha(source) {
                    return source
                }
                if let cutout = detection.cutout(instance: nil) {
                    return cutout
                }
                return try CharmImageProcessor.floodFillBackground(of: source)
            }
        }.value
    }

    /// Fits and analyses, then applies the user's size and weight.
    static func buildDraft(from isolated: CGImage, adjustments: StudioAdjustments) async throws -> StudioCharmDraft {
        try await Task.detached(priority: .userInitiated) {
            let square = try CharmImageProcessor.fitToSquare(isolated, fill: adjustments.fill)
            let analysis = try CharmImageProcessor.analyze(square)
            let metrics = CharmMetrics(
                mass: (analysis.metrics.mass * adjustments.weightScale).clamped(to: 0.5...9),
                radiusRatio: adjustments.sizeRatio,
                knotInset: analysis.metrics.knotInset
            )
            return StudioCharmDraft(
                square: square,
                metrics: metrics,
                palette: analysis.palette,
                analysedMass: analysis.metrics.mass
            )
        }.value
    }

    /// Encodes a draft for the store.
    static func processed(from draft: StudioCharmDraft) throws -> ProcessedCharmImage {
        ProcessedCharmImage(
            pngData: try CharmImageProcessor.encodePNG(draft.square),
            pixelSide: draft.square.width,
            metrics: draft.metrics,
            palette: draft.palette
        )
    }

    /// A display name from a file: the stem, tidied.
    static func suggestedName(for url: URL) -> String {
        // Leading dots mark a hidden file and are not part of a name. What remains
        // may be nothing but an extension, in which case the file has no name.
        let file = String(url.lastPathComponent.drop(while: { $0 == "." }))
        var stem = (file as NSString).deletingPathExtension
        if imageExtensions.contains(stem.lowercased()) {
            stem = ""
        }
        let tidied = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tidied.isEmpty ? "Custom Charm" : tidied
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "heif"]
}
