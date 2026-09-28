//
//  CharmLibraryGrid.swift
//  Hangly
//
//  The card grid and a single card.
//

import SwiftUI

/// A responsive grid of charm cards, or a friendly empty state.
struct CharmLibraryGrid: View {
    let viewModel: CharmLibraryViewModel

    private let columns = [GridItem(.adaptive(minimum: 136, maximum: 172), spacing: 14)]

    var body: some View {
        let items = viewModel.items

        if items.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(items) { item in
                        CharmCard(
                            item: item,
                            charm: viewModel.charm(for: item.id),
                            isSelected: viewModel.isSelected(item.id),
                            isFavorite: viewModel.isFavorite(item.id),
                            onSelect: { viewModel.select(item.id) },
                            onToggleFavorite: { viewModel.toggleFavorite(item.id) }
                        )
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One charm, live-rendered, with its name and region. Click to put it on the rope.
///
/// The card is a real `Button`, so it is reachable with Tab, activates with Space
/// or Return, and reads to VoiceOver as one control with the name, the region and
/// whether it is on the rope. The favourite star is a second, nested control.
struct CharmCard: View {
    let item: CharmLibraryItem
    let charm: any Charm
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            cardBody
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering && !reduceMotion ? 1.02 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
        .help(item.description)
        .accessibilityLabel("\(item.name), \(item.region)")
        .accessibilityValue(isSelected ? "On the rope" : "")
        .accessibilityHint("Puts this charm on the rope")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardBody: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                CharmView(charm: charm, inset: 0.78)
                    .frame(width: 104, height: 104)
                    .frame(maxWidth: .infinity)

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(isFavorite || isHovering ? 1 : 0)
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                .accessibilityLabel(isFavorite ? "Remove \(item.name) from favorites" : "Add \(item.name) to favorites")
            }

            VStack(spacing: 2) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.region)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(isHovering ? 0.06 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        // Top-leading, opposite the star, so neither badge sits on the caption.
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .padding(8)
                    .accessibilityLabel("On the rope")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
