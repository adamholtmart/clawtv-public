import Foundation

struct Channel: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let logoURL: URL?
    let streamURL: URL
    let groupTitle: String
    let tvgId: String?
    let country: String?
    let language: String?
    /// Optional sidecar subtitles (.srt/.vtt) advertised by the playlist via
    /// `tvg-subtitles=` or `subtitles=` attribute on the EXTINF line. VLC loads
    /// these as a "playback slave" alongside the main stream.
    let subtitleURL: URL?
    /// Catch-up template URL used by Xtream-style playlists. Supports the
    /// `${start}`, `${duration}` and `${end}` placeholders, expanded at
    /// playback time. Presence implies the channel supports time-shift.
    let catchupSource: String?
    /// Catch-up window in days advertised by the playlist (`catchup-days`).
    let catchupDays: Int?

    init(
        id: String = UUID().uuidString,
        name: String,
        logoURL: URL? = nil,
        streamURL: URL,
        groupTitle: String = "Uncategorized",
        tvgId: String? = nil,
        country: String? = nil,
        language: String? = nil,
        subtitleURL: URL? = nil,
        catchupSource: String? = nil,
        catchupDays: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.logoURL = logoURL
        self.streamURL = streamURL
        self.groupTitle = groupTitle
        self.tvgId = tvgId
        self.country = country
        self.language = language
        self.subtitleURL = subtitleURL
        self.catchupSource = catchupSource
        self.catchupDays = catchupDays
    }
}

struct ChannelGroup: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String
    let channels: [Channel]
}
