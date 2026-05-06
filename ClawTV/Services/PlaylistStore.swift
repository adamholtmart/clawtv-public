import Foundation
import SwiftUI

@MainActor
final class PlaylistStore: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var groups: [ChannelGroup] = []
    @Published private(set) var featuredChannels: [Channel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefresh: Date?
    @Published var errorMessage: String?
    @Published var favorites: Set<String> = []
    @Published var favoriteGroups: Set<String> = []
    @Published private(set) var recentlyWatched: [String] = []
    @Published var multiViewSeed: Channel?
    @Published var multiViewSlots: [Channel?]?
    @Published var multiViewAudioSlot: Int = 0
    @Published var resumeOnLaunchEnabled: Bool {
        didSet {
            CloudSync.shared.set(resumeOnLaunchEnabled, forKey: resumeOnLaunchKey)
        }
    }
    @Published var pendingResumeChannel: Channel?
    @Published var presentedScreen: PresentedScreen?
    @Published var localCity: String {
        didSet {
            CloudSync.shared.set(localCity, forKey: localCityKey)
        }
    }

    @Published var guidePinnedGroups: Set<String> = []

    private let playlistsKey = "clawtv.playlists.v1"
    private let favoritesKey = "clawtv.favorites.v1"
    private let favoriteGroupsKey = "clawtv.favoriteGroups.v1"
    private let guidePinnedGroupsKey = "clawtv.guidePinnedGroups.v1"
    private let recentsKey = "clawtv.recents.v1"
    private let lastRefreshKey = "clawtv.channels.lastRefresh.v1"
    private let resumeOnLaunchKey = "clawtv.resumeOnLaunch.v1"
    private let localCityKey = "clawtv.localCity.v1"
    private let groupFilterKey = "clawtv.groupFilter.v4.forceFull"
    private let refreshInterval: TimeInterval = 24 * 3600
    private let recentsCap = 20

    init() {
        self.resumeOnLaunchEnabled = CloudSync.shared.bool(forKey: resumeOnLaunchKey)
        self.localCity = CloudSync.shared.string(forKey: localCityKey) ?? ""
        load()
        computePendingResume()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudChange(_:)),
            name: .cloudSyncDidChange,
            object: nil
        )
    }

    var localChannels: [Channel] {
        let city = localCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { return [] }
        return channels.filter {
            $0.name.localizedCaseInsensitiveContains(city) ||
            $0.groupTitle.localizedCaseInsensitiveContains(city)
        }
    }

    private func computePendingResume() {
        guard resumeOnLaunchEnabled else { return }
        guard let firstID = recentlyWatched.first else { return }
        pendingResumeChannel = channels.first(where: { $0.id == firstID })
    }

    func clearPendingResume() {
        pendingResumeChannel = nil
    }

    func openChannel(_ channel: Channel,
                     siblings: [Channel] = [],
                     origin: PlaybackOrigin = .standalone,
                     epgChannelId: String? = nil) {
        presentedScreen = .player(PlaybackContext(channel: channel,
                                                  siblings: siblings,
                                                  origin: origin,
                                                  epgChannelId: epgChannelId))
    }

    func promoteFromMultiView(channel: Channel, slots: [Channel?], audioSlot: Int) {
        multiViewSlots = slots
        multiViewAudioSlot = audioSlot
        presentedScreen = .player(PlaybackContext(channel: channel, siblings: [], origin: .fromMultiView))
    }

    func returnToMultiView() {
        guard let slots = multiViewSlots,
              let firstChannel = slots.compactMap({ $0 }).first else {
            presentedScreen = nil
            return
        }
        presentedScreen = .multi(seed: firstChannel)
    }

    func consumeMultiViewSlots() -> (slots: [Channel?], audioSlot: Int)? {
        guard let s = multiViewSlots else { return nil }
        let result = (s, multiViewAudioSlot)
        multiViewSlots = nil
        return result
    }

    func closePlayback() {
        presentedScreen = nil
    }

    var activePlayback: PlaybackContext? {
        get {
            if case .player(let ctx) = presentedScreen { return ctx }
            return nil
        }
        set {
            if let ctx = newValue {
                presentedScreen = .player(ctx)
            } else if case .player = presentedScreen {
                presentedScreen = nil
            }
        }
    }

    func refreshIfStale() async {
        if let last = lastRefresh,
           Date().timeIntervalSince(last) < refreshInterval,
           !channels.isEmpty {
            return
        }
        await refresh()
    }

    private func rebuildDerived() {
        let grouped = Dictionary(grouping: channels, by: \.groupTitle)
        groups = grouped
            .map { ChannelGroup(name: $0.key, channels: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        featuredChannels = Array(channels.prefix(20))
        persistDerivedCache()
    }

    var favoriteChannels: [Channel] {
        channels.filter { favorites.contains($0.id) }
    }

    var recentlyWatchedChannels: [Channel] {
        let byID = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        return recentlyWatched.compactMap { byID[$0] }
    }

    func recordWatched(_ channel: Channel) {
        recentlyWatched.removeAll { $0 == channel.id }
        recentlyWatched.insert(channel.id, at: 0)
        if recentlyWatched.count > recentsCap {
            recentlyWatched = Array(recentlyWatched.prefix(recentsCap))
        }
        persistRecents()
    }

    func clearRecentlyWatched() {
        recentlyWatched = []
        persistRecents()
    }

    func clearChannelCache() {
        channels = []
        groups = []
        featuredChannels = []
        lastRefresh = nil
        UserDefaults.standard.removeObject(forKey: lastRefreshKey)
        if let url = channelsCacheURL() { try? FileManager.default.removeItem(at: url) }
        if let url = groupsCacheURL() { try? FileManager.default.removeItem(at: url) }
        Task { await refresh() }
    }

    func startMultiView(with channel: Channel) {
        multiViewSeed = channel
        presentedScreen = .multi(seed: channel)
    }

    func closeMultiView() {
        if case .multi = presentedScreen { presentedScreen = nil }
    }

    func consumeMultiViewSeed() -> Channel? {
        let c = multiViewSeed
        multiViewSeed = nil
        return c
    }

    func toggleFavorite(_ channel: Channel) {
        if favorites.contains(channel.id) {
            favorites.remove(channel.id)
        } else {
            favorites.insert(channel.id)
        }
        persistFavorites()
    }

    func isFavorite(_ channel: Channel) -> Bool {
        favorites.contains(channel.id)
    }

    func toggleFavoriteGroup(_ groupName: String) {
        if favoriteGroups.contains(groupName) {
            favoriteGroups.remove(groupName)
        } else {
            favoriteGroups.insert(groupName)
        }
        persistFavoriteGroups()
    }

    func isFavoriteGroup(_ groupName: String) -> Bool {
        favoriteGroups.contains(groupName)
    }

    var sortedGroups: [ChannelGroup] {
        let (favs, rest) = groups.reduce(into: ([ChannelGroup](), [ChannelGroup]())) { acc, g in
            if favoriteGroups.contains(g.name) {
                acc.0.append(g)
            } else {
                acc.1.append(g)
            }
        }
        return favs + rest
    }

    func addPlaylist(name: String, url: URL) async {
        let playlist = Playlist(name: name.isEmpty ? url.lastPathComponent : name, sourceURL: url)
        playlists.append(playlist)
        persistPlaylists()
        await refresh()
    }

    func removePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        persistPlaylists()
        Task { await refresh() }
    }

    func refresh() async {
        guard !playlists.isEmpty else {
            channels = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var all: [Channel] = []
        var anySucceeded = false
        for playlist in playlists {
            do {
                let (data, _) = try await URLSession.shared.data(from: playlist.sourceURL)
                guard let text = String(data: data, encoding: .utf8) else { continue }
                let parsed = try M3UParser.parse(text)
                all.append(contentsOf: parsed)
                anySucceeded = true
            } catch {
                errorMessage = "Failed to load \(playlist.name): \(error.localizedDescription)"
            }
        }
        guard anySucceeded, !all.isEmpty else { return }
        var seen = Set<String>()
        channels = all.filter { seen.insert($0.id).inserted }
        rebuildDerived()
        lastRefresh = Date()
        UserDefaults.standard.set(lastRefresh, forKey: lastRefreshKey)
        persistChannels()
    }

    private func load() {
        if let data = CloudSync.shared.data(forKey: playlistsKey),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
        if let data = CloudSync.shared.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favorites = decoded
        }
        if let data = CloudSync.shared.data(forKey: favoriteGroupsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            favoriteGroups = decoded
        }
        if let data = CloudSync.shared.data(forKey: guidePinnedGroupsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            guidePinnedGroups = decoded
        }
        if let data = CloudSync.shared.data(forKey: recentsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            recentlyWatched = decoded
        }
        if let ts = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date {
            lastRefresh = ts
        }
        loadCachedChannels()
        applyGroupFilterMigrationIfNeeded()
        if !playlists.isEmpty && channels.count < 1000 {
            Task { await refresh() }
        }
    }

    private func applyGroupFilterMigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: groupFilterKey) else { return }
        UserDefaults.standard.set(true, forKey: groupFilterKey)
        channels = []
        groups = []
        featuredChannels = []
        lastRefresh = nil
        UserDefaults.standard.removeObject(forKey: lastRefreshKey)
        if let url = channelsCacheURL() { try? FileManager.default.removeItem(at: url) }
        if let url = groupsCacheURL() { try? FileManager.default.removeItem(at: url) }
    }

    private func channelsCacheURL() -> URL? {
        let fm = FileManager.default
        guard let dir = try? fm.url(for: .cachesDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("channels.json")
    }

    private func groupsCacheURL() -> URL? {
        let fm = FileManager.default
        guard let dir = try? fm.url(for: .cachesDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("groups.json")
    }

    private func loadCachedChannels() {
        guard let url = channelsCacheURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Channel].self, from: data) else { return }
        channels = decoded
        if let gURL = groupsCacheURL(),
           let gData = try? Data(contentsOf: gURL),
           let cached = try? JSONDecoder().decode(DerivedCache.self, from: gData),
           cached.channelCount == decoded.count {
            groups = cached.groups
            featuredChannels = cached.featured
        } else {
            rebuildDerived()
        }
    }

    private func persistChannels() {
        guard let url = channelsCacheURL() else { return }
        if let data = try? JSONEncoder().encode(channels) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func persistDerivedCache() {
        guard let url = groupsCacheURL() else { return }
        let cache = DerivedCache(channelCount: channels.count, groups: groups, featured: featuredChannels)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private struct DerivedCache: Codable {
        let channelCount: Int
        let groups: [ChannelGroup]
        let featured: [Channel]
    }

    private func persistPlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            CloudSync.shared.set(data, forKey: playlistsKey)
        }
    }

    private func persistFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            CloudSync.shared.set(data, forKey: favoritesKey)
        }
    }

    func setGuidePinnedGroups(_ groups: Set<String>) {
        guidePinnedGroups = groups
        if let data = try? JSONEncoder().encode(groups) {
            CloudSync.shared.set(data, forKey: guidePinnedGroupsKey)
        }
    }

    private func persistFavoriteGroups() {
        if let data = try? JSONEncoder().encode(favoriteGroups) {
            CloudSync.shared.set(data, forKey: favoriteGroupsKey)
        }
    }

    private func persistRecents() {
        if let data = try? JSONEncoder().encode(recentlyWatched) {
            CloudSync.shared.set(data, forKey: recentsKey)
        }
    }

    // MARK: - iCloud incoming changes

    @objc private func handleCloudChange(_ notification: Notification) {
        guard let changed = notification.userInfo?["changedKeys"] as? [String] else { return }
        Task { @MainActor in
            var playlistsChanged = false
            for key in changed {
                switch key {
                case self.playlistsKey:
                    if let data = CloudSync.shared.data(forKey: key),
                       let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
                        self.playlists = decoded
                        playlistsChanged = true
                    }
                case self.favoritesKey:
                    if let data = CloudSync.shared.data(forKey: key),
                       let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
                        self.favorites = decoded
                    }
                case self.favoriteGroupsKey:
                    if let data = CloudSync.shared.data(forKey: key),
                       let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
                        self.favoriteGroups = decoded
                    }
                case self.guidePinnedGroupsKey:
                    if let data = CloudSync.shared.data(forKey: key),
                       let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
                        self.guidePinnedGroups = decoded
                    }
                case self.recentsKey:
                    if let data = CloudSync.shared.data(forKey: key),
                       let decoded = try? JSONDecoder().decode([String].self, from: data) {
                        self.recentlyWatched = decoded
                    }
                case self.resumeOnLaunchKey:
                    self.resumeOnLaunchEnabled = CloudSync.shared.bool(forKey: key)
                case self.localCityKey:
                    self.localCity = CloudSync.shared.string(forKey: key) ?? ""
                default:
                    break
                }
            }
            if playlistsChanged {
                await self.refresh()
            }
        }
    }
}

enum PlaybackOrigin {
    case standalone
    case fromMultiView
}

struct PlaybackContext: Identifiable {
    let id = UUID()
    let channel: Channel
    let siblings: [Channel]
    let origin: PlaybackOrigin
    let epgChannelId: String?

    init(channel: Channel,
         siblings: [Channel] = [],
         origin: PlaybackOrigin = .standalone,
         epgChannelId: String? = nil) {
        self.channel = channel
        self.siblings = siblings
        self.origin = origin
        self.epgChannelId = epgChannelId
    }
}

enum PresentedScreen: Identifiable {
    case player(PlaybackContext)
    case multi(seed: Channel)

    var id: String {
        switch self {
        case .player(let ctx): return "player-\(ctx.id.uuidString)"
        case .multi: return "multi"
        }
    }
}

