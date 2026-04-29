import Foundation
import SwiftUI
import Combine

/// Xtream Codes API client. Handles VOD (movies) and series catalog browse +
/// builds streaming URLs for playback. Credentials are stored in UserDefaults
/// and synced across devices via iCloud KVS.
@MainActor
final class XtreamService: ObservableObject {
    @Published var credentials: XtreamCredentials {
        didSet {
            persistCredentials()
            invalidate()
        }
    }
    @Published private(set) var movieCategories: [XtreamCategory] = []
    @Published private(set) var seriesCategories: [XtreamCategory] = []
    @Published private(set) var movies: [XtreamMovie] = []
    @Published private(set) var series: [XtreamSeries] = []
    @Published private(set) var seriesInfoCache: [Int: XtreamSeriesInfo] = [:]
    @Published private(set) var isLoadingMovies = false
    @Published private(set) var isLoadingSeries = false
    @Published var errorMessage: String?

    private let credsKey = "clawtv.xtream.creds.v1"
    private var cancellables: Set<AnyCancellable> = []

    var isConfigured: Bool { credentials.isComplete }

    init() {
        let defaultCreds = XtreamCredentials(server: "", username: "", password: "")
        let cloudData = CloudSync.shared.data(for: credsKey)
        if let data = cloudData ?? UserDefaults.standard.data(forKey: credsKey),
           let decoded = try? JSONDecoder().decode(XtreamCredentials.self, from: data) {
            self.credentials = decoded
        } else {
            self.credentials = defaultCreds
        }

        CloudSync.shared.externalChange
            .sink { [weak self] keys in
                guard let self else { return }
                Task { @MainActor in self.handleCloudChange(keys) }
            }
            .store(in: &cancellables)
    }

    private func handleCloudChange(_ keys: Set<String>) {
        guard keys.contains(credsKey),
              let data = CloudSync.shared.data(for: credsKey),
              let decoded = try? JSONDecoder().decode(XtreamCredentials.self, from: data),
              decoded != credentials else { return }
        credentials = decoded
    }

    private func persistCredentials() {
        if let data = try? JSONEncoder().encode(credentials) {
            UserDefaults.standard.set(data, forKey: credsKey)
            CloudSync.shared.set(data, for: credsKey)
        }
    }

    private func invalidate() {
        movieCategories = []
        seriesCategories = []
        movies = []
        series = []
        seriesInfoCache = [:]
    }

    // MARK: - Public API

    func loadMoviesIfNeeded() async {
        guard isConfigured, movies.isEmpty, !isLoadingMovies else { return }
        await loadMovies()
    }

    func loadSeriesIfNeeded() async {
        guard isConfigured, series.isEmpty, !isLoadingSeries else { return }
        await loadSeries()
    }

    func loadMovies() async {
        guard isConfigured else { return }
        isLoadingMovies = true
        defer { isLoadingMovies = false }
        do {
            async let cats: [XtreamCategory] = fetch(action: "get_vod_categories")
            async let allMovies: [XtreamMovie] = fetch(action: "get_vod_streams")
            let (c, m) = try await (cats, allMovies)
            movieCategories = c
            movies = m
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load movies: \(error.localizedDescription)"
        }
    }

    func loadSeries() async {
        guard isConfigured else { return }
        isLoadingSeries = true
        defer { isLoadingSeries = false }
        do {
            async let cats: [XtreamCategory] = fetch(action: "get_series_categories")
            async let all: [XtreamSeries] = fetch(action: "get_series")
            let (c, s) = try await (cats, all)
            seriesCategories = c
            series = s
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load series: \(error.localizedDescription)"
        }
    }

    func loadSeriesInfo(seriesID: Int) async -> XtreamSeriesInfo? {
        if let cached = seriesInfoCache[seriesID] { return cached }
        guard isConfigured, let url = apiURL(action: "get_series_info",
                                             extra: ["series_id": String(seriesID)]) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let info = try parseSeriesInfo(data: data)
            seriesInfoCache[seriesID] = info
            return info
        } catch {
            errorMessage = "Couldn't load season list: \(error.localizedDescription)"
            return nil
        }
    }

    /// Build a movie playback URL from Xtream credentials + stream id.
    func movieURL(for movie: XtreamMovie) -> URL? {
        guard let server = credentials.serverURL else { return nil }
        let ext = movie.containerExtension ?? "mp4"
        let path = "/movie/\(credentials.username)/\(credentials.password)/\(movie.streamID).\(ext)"
        return URL(string: server.absoluteString + path)
    }

    /// Build a series episode playback URL.
    func episodeURL(for episode: XtreamEpisode) -> URL? {
        guard let server = credentials.serverURL else { return nil }
        let ext = episode.containerExtension ?? "mp4"
        let path = "/series/\(credentials.username)/\(credentials.password)/\(episode.episodeID).\(ext)"
        return URL(string: server.absoluteString + path)
    }

    /// Wrap a movie or episode play URL into the Channel shape so it flows
    /// through the existing PlayerView path without adding a new presenter.
    func channel(forMovie movie: XtreamMovie) -> Channel? {
        guard let url = movieURL(for: movie) else { return nil }
        let logo = movie.icon.flatMap { URL(string: $0) }
        return Channel(id: "xtream-movie-\(movie.streamID)",
                       name: movie.name,
                       logoURL: logo,
                       streamURL: url,
                       groupTitle: "Movie")
    }

    func channel(forEpisode episode: XtreamEpisode, seriesName: String) -> Channel? {
        guard let url = episodeURL(for: episode) else { return nil }
        let logo = episode.still.flatMap { URL(string: $0) }
        return Channel(id: "xtream-episode-\(episode.episodeID)",
                       name: "\(seriesName) — \(episode.title)",
                       logoURL: logo,
                       streamURL: url,
                       groupTitle: seriesName)
    }

    // MARK: - HTTP

    private func apiURL(action: String, extra: [String: String] = [:]) -> URL? {
        guard let server = credentials.serverURL else { return nil }
        var components = URLComponents(url: server.appendingPathComponent("player_api.php"),
                                       resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
            URLQueryItem(name: "action", value: action)
        ]
        for (k, v) in extra { items.append(URLQueryItem(name: k, value: v)) }
        components?.queryItems = items
        return components?.url
    }

    private func fetch<T: Decodable>(action: String, extra: [String: String] = [:]) async throws -> [T] {
        guard let url = apiURL(action: action, extra: extra) else {
            throw NSError(domain: "Xtream", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([T].self, from: data)
    }

    private func parseSeriesInfo(data: Data) throws -> XtreamSeriesInfo {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let episodesByKey = root["episodes"] as? [String: Any] else {
            return XtreamSeriesInfo(seasons: [])
        }
        var seasons: [XtreamSeason] = []
        for (key, value) in episodesByKey {
            guard let arr = value as? [[String: Any]],
                  let seasonNumber = Int(key) else { continue }
            let episodes: [XtreamEpisode] = arr.compactMap { dict in
                guard let id = (dict["id"] as? String) ?? (dict["id"] as? Int).map(String.init),
                      let episodeID = Int(id),
                      let title = dict["title"] as? String else { return nil }
                let info = dict["info"] as? [String: Any]
                let plot = info?["plot"] as? String
                let runtime = info?["duration_secs"].flatMap {
                    ($0 as? Int).map { String($0 / 60) }
                }
                let rating = (info?["rating"] as? String)
                    ?? (info?["rating"] as? Double).map { String($0) }
                let still = info?["movie_image"] as? String
                let ext = dict["container_extension"] as? String
                let epNum = (dict["episode_num"] as? Int)
                    ?? (dict["episode_num"] as? String).flatMap(Int.init)
                    ?? 0
                return XtreamEpisode(id: id,
                                     episodeID: episodeID,
                                     title: title,
                                     seasonNumber: seasonNumber,
                                     episodeNumber: epNum,
                                     containerExtension: ext,
                                     plot: plot,
                                     runtime: runtime,
                                     rating: rating,
                                     still: still)
            }
            .sorted { $0.episodeNumber < $1.episodeNumber }
            seasons.append(XtreamSeason(number: seasonNumber, episodes: episodes))
        }
        seasons.sort { $0.number < $1.number }
        return XtreamSeriesInfo(seasons: seasons)
    }
}
