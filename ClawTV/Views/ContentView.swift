import SwiftUI

enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case home, guide, search, favorites, all, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .guide: return "Guide"
        case .search: return "Search"
        case .favorites: return "Favorites"
        case .all: return "All"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .guide: return "calendar.day.timeline.left"
        case .search: return "magnifyingglass"
        case .favorites: return "star.fill"
        case .all: return "square.grid.3x3.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Top-level router. Decides between onboarding, paywall, and the main shell.
struct RootView: View {
    @EnvironmentObject var store: PlaylistStore
    @EnvironmentObject var entitlement: EntitlementStore

    var body: some View {
        if !entitlement.hasAccess {
            PaywallView()
        } else if store.playlists.isEmpty {
            OnboardingView()
        } else {
            MainShellView()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: PlaylistStore

    var body: some View {
        if store.playlists.isEmpty {
            OnboardingView()
        } else {
            MainShellView()
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject var store: PlaylistStore
    @EnvironmentObject var epg: EPGService
    @EnvironmentObject var resolver: ChannelResolver
    @State private var selectedTab: MainTab = .home
    @State private var preloadKey: String = ""
    @State private var preparedCount: Int = 0

    private var preloadInputKey: String {
        "\(epg.epgChannels.count)|\(store.channels.count)|\(resolver.learnedPicks.count)|\(resolver.recentEPGIds.count)"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label(MainTab.home.title, systemImage: MainTab.home.systemImage) }
                .tag(MainTab.home)

            guideTab

            SearchView()
                .tabItem { Label(MainTab.search.title, systemImage: MainTab.search.systemImage) }
                .tag(MainTab.search)

            FavoritesView()
                .tabItem { Label(MainTab.favorites.title, systemImage: MainTab.favorites.systemImage) }
                .tag(MainTab.favorites)

            AllChannelsView()
                .tabItem { Label(MainTab.all.title, systemImage: MainTab.all.systemImage) }
                .tag(MainTab.all)

            SettingsView()
                .tabItem { Label(MainTab.settings.title, systemImage: MainTab.settings.systemImage) }
                .tag(MainTab.settings)
        }
        .onChange(of: epg.isGuideReady) { _, ready in
            // Only bounce if the Guide has never been ready (initial download path).
            // Once ready, `isGuideReady` latches — background reloads must not
            // swap the user off the Guide tab or unmount GuideView mid-interaction.
            if !ready, !epg.hasEverBeenReady, selectedTab == .guide {
                selectedTab = .home
            }
        }
        .onAppear {
            if let c = store.pendingResumeChannel {
                store.openChannel(c, siblings: store.recentlyWatchedChannels)
                store.clearPendingResume()
            }
        }
        .task(id: preloadInputKey) {
            await preloadProgrammesForCuratedSet()
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.presentedScreen != nil },
            set: { if !$0 { store.presentedScreen = nil } }
        )) {
            PresentedScreenHost(selectedTab: $selectedTab)
                .environmentObject(store)
                .environmentObject(epg)
        }
    }

    @ViewBuilder
    private var guideTab: some View {
        if epg.isGuideReady {
            GuideView()
                .tabItem { Label(MainTab.guide.title, systemImage: MainTab.guide.systemImage) }
                .tag(MainTab.guide)
        } else {
            GuideLoadingView(preparedCount: preparedCount)
                .tabItem {
                    Label(guideLoadingLabel, systemImage: "hourglass")
                }
                .tag(MainTab.guide)
                .disabled(true)
        }
    }

    private var guideLoadingLabel: String {
        if epg.isLoading { return "Guide (downloading)" }
        if epg.isLoadingProgrammes { return "Guide (loading)" }
        return "Guide (preparing)"
    }

    private func preloadProgrammesForCuratedSet() async {
        let key = preloadInputKey
        guard key != preloadKey, !epg.epgChannels.isEmpty else { return }
        let all = epg.epgChannels
        let learned = Set(resolver.learnedPicks.keys)
        let recent = resolver.recentEPGIds
        let allowedM3U = store.channels
        let res = resolver
        let ids: Set<String> = await Task.detached(priority: .userInitiated) {
            let reachable = await res.reachableEPGIds(epgChannels: all, m3u: allowedM3U)
            guard !reachable.isEmpty else { return Set<String>() }
            let eligible = all.filter { reachable.contains($0.id) }
            return Set(GuideCurator.curate(epgChannels: eligible,
                                           learnedEPGIds: learned,
                                           recentEPGIds: recent).map(\.id))
        }.value
        guard !ids.isEmpty else { return }
        preloadKey = key
        preparedCount = ids.count
        await epg.loadProgrammes(for: ids)
    }
}

struct GuideLoadingView: View {
    @EnvironmentObject var epg: EPGService
    let preparedCount: Int

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(title)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        if epg.isLoading { return "Downloading guide data…" }
        if epg.isLoadingProgrammes { return "Preparing guide…" }
        return "Guide is getting ready…"
    }

    private var subtitle: String {
        if epg.epgChannels.isEmpty { return "First-time download — this only happens once." }
        if preparedCount > 0 {
            return "Loading \(preparedCount) matched channels"
        }
        return "Matching streams to guide…"
    }
}

struct PresentedScreenHost: View {
    @EnvironmentObject var store: PlaylistStore
    @EnvironmentObject var epg: EPGService
    @Binding var selectedTab: MainTab

    var body: some View {
        Group {
            switch store.presentedScreen {
            case .player(let context):
                PlayerView(
                    channel: context.channel,
                    siblings: context.siblings,
                    origin: context.origin,
                    epgChannelId: context.epgChannelId,
                    onSelectTab: { tab in
                        store.presentedScreen = nil
                        selectedTab = tab
                    }
                )
                .id("player-\(context.id.uuidString)")
            case .multi:
                MultiView(onExit: { store.closeMultiView() })
                    .id("multi")
            case .none:
                Color.black
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: store.presentedScreen?.id)
    }
}
