//
//  CharmDetailPane.swift
//  Hangly
//
//  The right-hand pane: whatever is on the rope, large, with its story.
//

import SwiftUI

/// Live preview and metadata for the selected charm.
struct CharmDetailPane: View {
    let viewModel: CharmLibraryViewModel

    var body: some View {
        if let item = viewModel.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CharmView(charm: viewModel.charm(for: item.id), inset: 0.80)
                        .frame(width: 180, height: 180)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.title2.weight(.semibold))
                        Text(item.region.uppercased())
                            .font(.caption.weight(.medium))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.description)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)

                    TagCloud(tags: item.tags)

                    Divider()

                    HStack(spacing: 8) {
                        Label("On the rope", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Button {
                            viewModel.toggleFavorite(item.id)
                        } label: {
                            Image(systemName: viewModel.isFavorite(item.id) ? "star.fill" : "star")
                        }
                        .help(viewModel.isFavorite(item.id) ? "Remove from Favorites" : "Add to Favorites")
                        .accessibilityLabel(
                            viewModel.isFavorite(item.id) ? "Remove from favorites" : "Add to favorites"
                        )
                    }

                    if item.isCustom {
                        Button(role: .destructive) {
                            viewModel.deleteSelected()
                        } label: {
                            Label("Delete Charm…", systemImage: "trash")
                        }
                        .disabled(!viewModel.canDeleteSelected)
                    }
                }
                .padding(18)
            }
        } else {
            ContentUnavailableView("Nothing on the rope", systemImage: "circle.dashed")
        }
    }
}

/// Small capsule labels that wrap onto as many lines as they need.
struct TagCloud: View {
    let tags: [String]

    var body: some View {
        WrappingHStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        }
    }
}

/// A horizontal flow that wraps, using the `Layout` protocol.
struct WrappingHStack: Layout {
    var spacing: Double = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 260, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrange(width: bounds.width, subviews: subviews).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(width: Double, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x = 0.0
        var y = 0.0
        var rowHeight = 0.0
        var maxX = 0.0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}
