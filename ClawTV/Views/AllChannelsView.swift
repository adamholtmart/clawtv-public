import SwiftUI

struct AllChannelsView: View {
    @EnvironmentObject var store: PlaylistStore
    @Environment(\.channelPickAction) private var pickAction
    @State private var searchText = ""
    @State private var selectedGroup: String? = nil

    private var filteredChannels: [Channel] {
        var result = store.channels
        if let group = selectedGroup {
            result = result.filter { $0.groupTitle == group }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    private var groupNames: [String] {
        let all = Array(Set(store.channels.map(\.groupTitle))).sorted()
        let favs = all.filter { store.isFavoriteGroup($0) }
        let rest = all.filter { !store.isFavoriteGroup($0) }
        return favs + rest
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        GroupChip(title: "All", isSelected: selectedGroup == nil) {
                            selectedGroup = nil
                        }
                        ForEach(groupNames, id: \.self) { name in
                            GroupChip(title: name, isSelected: selectedGroup == name) {
                                selectedGroup = (selectedGroup == name) ? nil : name
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 24)
                }

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(260), spacing: 28), count: 5), spacing: 36) {
                        ForEach(filteredChannels) { channel in
                            Button {
                                if let pickAction { pickAction(channel) }
                                else { store.openChannel(channel, siblings: filteredChannels) }
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
                    .padding(40)
                }
            }
            .searchable(text: $searchText, prompt: "Search channels")
        }
    }
}

struct GroupChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isFocused ? Color.white :
                                (isSelected ? Color.white.opacity(0.45) : Color.clear),
                            lineWidth: isFocused ? 2 : 1
                        )
                )
                .foregroundStyle(isSelected || isFocused ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
