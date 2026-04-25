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
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 28), count: 5), spacing: 36) {
                            ForEach(store.favoriteChannels) { channel in
                                Button {
                                    if let pickAction { pickAction(channel) }
                                    else { store.openChannel(channel, siblings: store.favoriteChannels) }
                                } label: {
                                    ChannelCard(channel: channel)
                                }
                                .buttonStyle(.card)
                                .contextMenu {
                                    Button {
                                        store.toggleFavorite(channel)
                                    } label: {
                                        Label("Remove from Favorites", systemImage: "star.slash")
                                    }
                                }
                            }
                        }
                        .padding(40)
                    }
                }
            }
        }
    }
}
