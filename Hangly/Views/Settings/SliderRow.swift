//
//  SliderRow.swift
//  Hangly
//
//  Reusable labelled slider used across the Settings tabs.
//

import SwiftUI

/// A form row pairing a slider with its current value.
///
/// The read-out uses monospaced digits and a fixed width so the row does not shift
/// horizontally while the user drags.
struct SliderRow: View {
    let title: String
    let valueDescription: String
    let range: ClosedRange<Double>
    @Binding var value: Double

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                    .accessibilityLabel(title)
                    .accessibilityValue(valueDescription)

                Text(valueDescription)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}
