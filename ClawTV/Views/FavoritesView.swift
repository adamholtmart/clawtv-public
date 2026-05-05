import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var store: PlaylistStore
    @Environment(\.channelPickAction) private var pickAction

    var body: some View {
        NavigationStack {
            Group {
                if store.favoriteChannels.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 80))
                            .foregroundStyle(.secondary)
                        Text("No favorites yet")
                            .font(.title)
                        Text("Press and hold a channel to mark it as a favorite.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: Layout.cardColumns, spacing: 36) {
                            ForEach(store.favoriteChannels) { channel in
                                Button {
                                    if let pickAction { pickAction(channel) }
                                    else { store.openChannel(channel, siblings: store.favoriteChannels) }
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
                                        Label("Remove from Favorites", systemImage: "star.slash")
                                    }
                                }
                            }
                        }
                        .padding(Layout.hPad)
                    }
                }
            }
        }
    }
}
