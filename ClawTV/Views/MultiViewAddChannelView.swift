import SwiftUI

struct MultiViewAddChannelView: View {
    let slotIndex: Int
    let currentChannel: Channel?
    let onPick: (Channel) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var store: PlaylistStore
    @State private var selectedTab: PickerTab = .home

    private enum PickerTab: String, CaseIterable, Identifiable, Hashable {
        case home, search, favorites, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: return "Home"
            case .search: return "Search"
            case .favorites: return "Favorites"
            case .all: return "All"
            }
        }
        var systemImage: String {
            switch self {
            case .home: return "house.fill"
            case .search: return "magnifyingglass"
            case .favorites: return "star.fill"
            case .all: return "square.grid.3x3.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label(PickerTab.home.title, systemImage: PickerTab.home.systemImage) }
                    .tag(PickerTab.home)

                SearchView()
                    .tabItem { Label(PickerTab.search.title, systemImage: PickerTab.search.systemImage) }
                    .tag(PickerTab.search)

                FavoritesView()
                    .tabItem { Label(PickerTab.favorites.title, systemImage: PickerTab.favorites.systemImage) }
                    .tag(PickerTab.favorites)

                AllChannelsView()
                    .tabItem { Label(PickerTab.all.title, systemImage: PickerTab.all.systemImage) }
                    .tag(PickerTab.all)
            }
            .environment(\.channelPickAction, ChannelPickAction(handler: onPick))
        }
        .overlay(alignment: .topTrailing) {
            ReplacingBadge(
                slotIndex: slotIndex,
                channel: currentChannel,
                onCancel: onCancel
            )
            .padding(.top, 24)
            .padding(.trailing, 60)
        }
        .onExitCommand { onCancel() }
    }
}

private struct ReplacingBadge: View {
    let slotIndex: Int
    let channel: Channel?
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: channel == nil ? "plus.rectangle.on.rectangle" : "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(channel == nil ? "ADDING TO SLOT \(slotIndex + 1)" : "REPLACING IN SLOT \(slotIndex + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tint)
                    .tracking(0.8)
                Text(channel?.name ?? "Pick a channel")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(10)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
