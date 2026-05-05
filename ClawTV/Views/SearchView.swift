import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: PlaylistStore
    @Environment(\.channelPickAction) private var pickAction
    @State private var searchText = ""
    @State private var selectedGroup: String? = nil
    @State private var results: [Channel] = []
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    private var groupNames: [String] {
        store.sortedGroups.map(\.name)
    }

    private var searchKey: String {
        "\(selectedGroup ?? "")\u{1F}\(searchText)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    categoryStrip
                    gridView
                }
            }
            .onAppear { searchFocused = true }
            .task(id: searchKey) {
                await runSearch()
            }
        }
    }

    private func runSearch() async {
        let text = searchText
        let group = selectedGroup

        if text.isEmpty && group == nil {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        try? await Task.sleep(nanoseconds: 180_000_000) // 180ms debounce
        if Task.isCancelled { return }

        let all = store.channels
        let favs = store.favoriteChannels

        let filtered: [Channel] = await Task.detached(priority: .userInitiated) {
            var pool: [Channel]
            if group == "__favorites__" {
                pool = favs
            } else if let g = group {
                pool = all.filter { $0.groupTitle == g }
            } else {
                pool = all
            }
            if !text.isEmpty {
                let q = text.lowercased()
                let matches = pool.compactMap { ch -> (Channel, Bool, Int)? in
                    let lname = ch.name.lowercased()
                    guard lname.contains(q) else { return nil }
                    return (ch, lname.hasPrefix(q), ch.name.count)
                }
                pool = matches
                    .sorted { lhs, rhs in
                        if lhs.1 != rhs.1 { return lhs.1 }
                        return lhs.2 < rhs.2
                    }
                    .map(\.0)
            }
            return Array(pool.prefix(300))
        }.value

        if Task.isCancelled { return }
        results = filtered
        isSearching = false
    }

    private var header: some View {
        HStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search channels", text: $searchText)
                #if os(tvOS)
                .font(.system(size: 36, weight: .semibold))
                #else
                .font(.system(size: 20, weight: .semibold))
                #endif
                .textFieldStyle(.plain)
                .focused($searchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
            }

            if isSearching {
                ProgressView()
                    .frame(minWidth: 120, alignment: .trailing)
            } else if !searchText.isEmpty || selectedGroup != nil {
                Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 120, alignment: .trailing)
            }
        }
        .padding(.horizontal, Layout.hPad)
        .padding(.top, 40)
        .padding(.bottom, 24)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                GroupChip(title: "All", isSelected: selectedGroup == nil) {
                    selectedGroup = nil
                }
                if !store.favoriteChannels.isEmpty {
                    GroupChip(title: "★ Favorites", isSelected: selectedGroup == "__favorites__") {
                        selectedGroup = selectedGroup == "__favorites__" ? nil : "__favorites__"
                    }
                }
                ForEach(groupNames, id: \.self) { g in
                    GroupChip(title: g, isSelected: selectedGroup == g) {
                        selectedGroup = selectedGroup == g ? nil : g
                    }
                }
            }
            .padding(.horizontal, Layout.hPad)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private var gridView: some View {
        if searchText.isEmpty && selectedGroup == nil {
            idlePane
        } else if isSearching && results.isEmpty {
            loadingPane
        } else if results.isEmpty {
            emptyPane
        } else {
            resultsGrid
        }
    }

    private var idlePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                if !store.recentlyWatchedChannels.isEmpty {
                    ChannelRow(title: "Recently Watched", channels: store.recentlyWatchedChannels)
                }
                if !store.favoriteChannels.isEmpty {
                    ChannelRow(title: "Favorites", channels: store.favoriteChannels)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tip")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Layout.hPad)
                    Text("Start typing to search across all \(store.channels.count) channels, or tap a category chip above to browse.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Layout.hPad)
                }
            }
            .padding(.vertical, 32)
        }
    }

    private var loadingPane: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Searching\u{2026}")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var emptyPane: some View {
        VStack(spacing: 12) {
            Image(systemName: "tv.slash")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No channels in this category" : "No matches for \u{201C}\(searchText)\u{201D}")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: Layout.cardColumns, spacing: 36) {
                ForEach(results) { channel in
                    Button {
                        if let pickAction { pickAction(channel) }
                        else { store.openChannel(channel, siblings: results) }
                    } label: {
                        ChannelCard(channel: channel)
                    }
                    #if os(tvOS)
                    .buttonStyle(.card)
                    #else
                    .buttonStyle(.channelCard)
                    #endif
                    .contextMenu {
                        Button {
                            store.toggleFavorite(channel)
                        } label: {
                            if store.isFavorite(channel) {
                                Label("Remove from Favorites", systemImage: "star.slash")
                            } else {
                                Label("Add to Favorites", systemImage: "star")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.hPad)
            .padding(.vertical, 32)
        }
    }
}
