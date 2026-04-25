import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: PlaylistStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    if store.isLoading && store.channels.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Loading channels…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 60)
                    }

                    LocalsRow()

                    if !store.recentlyWatchedChannels.isEmpty {
                        ChannelRow(title: "Recently Watched", channels: store.recentlyWatchedChannels)
                    }

                    if !store.favoriteChannels.isEmpty {
                        ChannelRow(title: "Favorites", channels: store.favoriteChannels)
                    }

                    if !store.featuredChannels.isEmpty {
                        ChannelRow(title: "Featured", channels: store.featuredChannels)
                    }

                    if !store.groups.isEmpty {
                        CategoryGrid(title: "Browse Categories", groups: store.sortedGroups)
                    }
                }
                .padding(.vertical, 40)
            }
        }
    }
}

struct LocalsRow: View {
    @EnvironmentObject var store: PlaylistStore
    @Environment(\.channelPickAction) private var pickAction

    var body: some View {
        let city = store.localCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let locals = store.localChannels

        if !city.isEmpty && !locals.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.tint)
                    Text("Locals — \(city)")
                        .font(.title2).fontWeight(.semibold)
                    Text("\(locals.count) channels")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 60)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 32) {
                        ForEach(locals) { channel in
                            Button {
                                if let pickAction { pickAction(channel) }
                                else { store.openChannel(channel, siblings: locals) }
                            } label: {
                                ChannelCard(channel: channel)
                            }
                            .buttonStyle(.card)
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
                    .padding(.horizontal, 60)
                    .padding(.vertical, 20)
                }
            }
        } else if city.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "location.slash")
                        .foregroundStyle(.secondary)
                    Text("Set your city in Settings to see Local channels")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 60)
            }
        }
    }
}

struct CategoryGrid: View {
    let title: String
    let groups: [ChannelGroup]
    @EnvironmentObject var store: PlaylistStore

    private let columns = Array(repeating: GridItem(.fixed(380), spacing: 24), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 60)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(groups) { group in
                    NavigationLink {
                        GroupChannelsView(group: group)
                    } label: {
                        CategoryTile(group: group, isFavorite: store.isFavoriteGroup(group.name))
                    }
                    .buttonStyle(.card)
                    .contextMenu {
                        Button {
                            store.toggleFavoriteGroup(group.name)
                        } label: {
                            if store.isFavoriteGroup(group.name) {
                                Label("Unpin from Top", systemImage: "pin.slash")
                            } else {
                                Label("Pin to Top", systemImage: "pin")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 20)
        }
    }
}

struct CategoryTile: View {
    let group: ChannelGroup
    let isFavorite: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: isFavorite
                        ? [Color(red: 0.24, green: 0.20, blue: 0.05), Color(white: 0.08)]
                        : [Color(white: 0.18), Color(white: 0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(group.channels.count) channels")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.yellow)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: 380, height: 110)
    }
}

struct GroupChannelsView: View {
    let group: ChannelGroup
    @EnvironmentObject var store: PlaylistStore
    @Environment(\.channelPickAction) private var pickAction

    private let columns = Array(repeating: GridItem(.fixed(260), spacing: 32), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 32) {
                ForEach(group.channels) { channel in
                    Button {
                        if let pickAction { pickAction(channel) }
                        else { store.openChannel(channel, siblings: group.channels) }
                    } label: {
                        ChannelCard(channel: channel)
                    }
                    .buttonStyle(.card)
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
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
        .navigationTitle(group.name)
    }
}

struct ChannelRow: View {
    let title: String
    let channels: [Channel]
    @EnvironmentObject var store: PlaylistStore
    @Environment(\.channelPickAction) private var pickAction

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 60)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 32) {
                    ForEach(channels) { channel in
                        Button {
                            if let pickAction { pickAction(channel) }
                            else { store.openChannel(channel, siblings: channels) }
                        } label: {
                            ChannelCard(channel: channel)
                        }
                        .buttonStyle(.card)
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
                .padding(.horizontal, 60)
                .padding(.vertical, 20)
            }
        }
    }
}
