//
//  CharmStudioPanels.swift
//  Hangly
//
//  The source panel (what came in, how the background goes) and the properties
//  panel (what the charm becomes).
//

import SwiftUI

/// The source image and the background-removal controls.
struct StudioSourcePanel: View {
    let viewModel: CharmStudioViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Source").font(.headline)

                if let image = viewModel.sourceImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Source image, \(image.width) by \(image.height) pixels")
                }
                if let url = viewModel.sourceURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Divider()

                Text("Background").font(.headline)
                Picker("Method", selection: methodBinding) {
                    ForEach(SubjectRemoval.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityLabel("Background removal method")

                methodDetail
            }
            .padding(14)
        }
    }

    /// Only the parts that apply to the chosen method.
    @ViewBuilder private var methodDetail: some View {
        switch viewModel.adjustments.removal {
        case .detectedSubject(let instance):
            if viewModel.detection.instanceCount > 1 {
                Picker("Subject", selection: instanceBinding(current: instance)) {
                    Text("All").tag(Int?.none)
                    ForEach(1...viewModel.detection.instanceCount, id: \.self) { number in
                        Text("\(number)").tag(Int?.some(number))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Which detected subject to keep")
            } else if !viewModel.detection.hasSubject {
                Text("No subject was detected in this image.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .flatBackground(let tolerance):
            SliderRow(
                title: "Tolerance",
                valueDescription: "\(tolerance)",
                range: Self.toleranceSliderRange,
                value: toleranceBinding(current: tolerance)
            )
            Text("How different from the corner colour a pixel may be and still count as background.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .automatic:
            Text("Existing transparency is kept. Otherwise the detected subject is used, then a flat-background fill.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .keepOriginal:
            Text("The image is used exactly as it is.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let toleranceSliderRange: ClosedRange<Double> =
        Double(StudioAdjustments.toleranceRange.lowerBound)...Double(StudioAdjustments.toleranceRange.upperBound)

    private var methodBinding: Binding<SubjectRemoval.Kind> {
        Binding(
            get: { viewModel.adjustments.removal.kind },
            set: { kind in
                viewModel.apply { adjustments in
                    switch kind {
                    case .automatic: adjustments.removal = .automatic
                    case .detectedSubject: adjustments.removal = .detectedSubject(instance: nil)
                    case .flatBackground:
                        adjustments.removal = .flatBackground(tolerance: SubjectRemoval.defaultTolerance)
                    case .keepOriginal: adjustments.removal = .keepOriginal
                    }
                }
            }
        )
    }

    private func instanceBinding(current: Int?) -> Binding<Int?> {
        Binding(
            get: { current },
            set: { instance in viewModel.apply { $0.removal = .detectedSubject(instance: instance) } }
        )
    }

    private func toleranceBinding(current: Int) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { value in
                viewModel.apply({ $0.removal = .flatBackground(tolerance: Int(value.rounded())) }, recordUndo: false)
            }
        )
    }
}

/// Name, size, weight and fill.
struct StudioPropertiesPanel: View {
    let viewModel: CharmStudioViewModel

    @FocusState private var nameIsFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Charm").font(.headline)

                TextField("Name", text: nameBinding, prompt: Text(viewModel.effectiveName))
                    .textFieldStyle(.roundedBorder)
                    .focused($nameIsFocused)
                    .onChange(of: nameIsFocused) { _, focused in
                        focused ? viewModel.beginEditing() : viewModel.endEditing()
                    }
                    .accessibilityLabel("Charm name")

                SliderRow(
                    title: "Size",
                    valueDescription: viewModel.adjustments.sizeRatio.formatted(.percent.precision(.fractionLength(0))),
                    range: StudioAdjustments.sizeRange,
                    value: continuousBinding(\.sizeRatio)
                )
                SliderRow(
                    title: "Weight",
                    valueDescription: weightDescription,
                    range: StudioAdjustments.weightRange,
                    value: continuousBinding(\.weightScale)
                )
                SliderRow(
                    title: "Fill",
                    valueDescription: viewModel.adjustments.fill.formatted(.percent.precision(.fractionLength(0))),
                    range: StudioAdjustments.fillRange,
                    value: continuousBinding(\.fill)
                )

                if let draft = viewModel.draft {
                    Divider()
                    Text("Physics").font(.headline)
                    LabeledContent("Mass") {
                        Text(draft.metrics.mass.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                    }
                    LabeledContent("Analysed") {
                        Text(draft.analysedMass.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text("Mass comes from how much of the square the image fills, times your weight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        // Sliders drive `apply` without recording; the drag is recorded as one
        // step by the editing hooks, which SliderRow does not expose, so the
        // panel wraps its sliders in begin/end on hover-press instead.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in viewModel.beginEditing() }
                .onEnded { _ in viewModel.endEditing() }
        )
    }

    private var weightDescription: String {
        "×" + viewModel.adjustments.weightScale.formatted(.number.precision(.fractionLength(2)))
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { viewModel.adjustments.name },
            set: { value in viewModel.apply({ $0.name = value }, recordUndo: false) }
        )
    }

    private func continuousBinding(_ keyPath: WritableKeyPath<StudioAdjustments, Double>) -> Binding<Double> {
        Binding(
            get: { viewModel.adjustments[keyPath: keyPath] },
            set: { value in viewModel.apply({ $0[keyPath: keyPath] = value }, recordUndo: false) }
        )
    }
}
