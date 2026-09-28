//
//  CharmLibraryView.swift
//  Hangly
//
//  The Charm Library window.
//

import OSLog
import SwiftUI

/// Browse, search, star and switch charms.
///
/// A sidebar of categories, a searchable grid of live-rendered cards, and a detail
/// pane for whatever is on the rope. Clicking a card switches the rope at once and
/// the pane follows, so the window is both the catalogue and the preview.
struct CharmLibraryView: View {
    static let windowID = "charm-library"

    @State private var viewModel: CharmLibraryViewModel

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: environment.makeCharmLibraryViewModel())
    }

    var body: some View {
        NavigationSplitView {
            CharmLibrarySidebar(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            CharmLibraryContent(viewModel: viewModel)
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search charms")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.importImage()
                } label: {
                    Label("Import Image…", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.isImporting)
                .help("Import a PNG, JPEG or WebP as a charm")
            }
        }
        .navigationTitle("Charm Library")
        .frame(minWidth: 820, minHeight: 520)
        .onAppear {
            Logger.app.diagnostic("Charm Library opened.")
        }
    }
}

/// Grid on the left, detail on the right. Split out so it can be rendered on its
/// own, without the window chrome, for previews and offscreen checks.
struct CharmLibraryContent: View {
    let viewModel: CharmLibraryViewModel

    var body: some View {
        HStack(spacing: 0) {
            CharmLibraryGrid(viewModel: viewModel)
            Divider()
            CharmDetailPane(viewModel: viewModel)
                .frame(width: 272)
        }
    }
}

/// Browse groups on the left.
struct CharmLibrarySidebar: View {
    @Bindable var viewModel: CharmLibraryViewModel

    var body: some View {
        List(selection: $viewModel.filter) {
            Section("Browse") {
                Label("All Charms", systemImage: "square.grid.2x2")
                    .tag(CharmLibraryViewModel.Filter.all)
                Label {
                    HStack {
                        Text("Favorites")
                        if viewModel.favoriteCount > 0 {
                            Spacer()
                            Text("\(viewModel.favoriteCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } icon: {
                    Image(systemName: "star")
                }
                .tag(CharmLibraryViewModel.Filter.favorites)
            }

            Section("Categories") {
                ForEach(viewModel.categories) { category in
                    Label(category.name, systemImage: symbol(for: category.id))
                        .tag(CharmLibraryViewModel.Filter.category(category.id))
                }
            }

            if viewModel.hasCustomCharms {
                Section("Imported") {
                    Label("Yours", systemImage: "photo.on.rectangle")
                        .tag(CharmLibraryViewModel.Filter.yours)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func symbol(for categoryID: String) -> String {
        switch categoryID {
        case "protection": "shield.lefthalf.filled"
        case "luck": "sparkles"
        case "ritual": "house"
        case "classic": "circle.hexagongrid"
        default: "tag"
        }
    }
}
