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

    init(
        id: String = UUID().uuidString,
        name: String,
        logoURL: URL? = nil,
        streamURL: URL,
        groupTitle: String = "Uncategorized",
        tvgId: String? = nil,
        country: String? = nil,
        language: String? = nil
    ) {
        self.id = id
        self.name = name
        self.logoURL = logoURL
        self.streamURL = streamURL
        self.groupTitle = groupTitle
        self.tvgId = tvgId
        self.country = country
        self.language = language
    }
}

struct ChannelGroup: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String
    let channels: [Channel]
}
