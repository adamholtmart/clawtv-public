import Foundation

struct XtreamCredentials: Codable, Equatable {
    var server: String
    var username: String
    var password: String

    var isComplete: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.isEmpty
            && !password.isEmpty
    }

    var serverURL: URL? {
        let trimmed = server.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") { return URL(string: trimmed) }
        return URL(string: "http://\(trimmed)")
    }
}

struct XtreamCategory: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let parentID: String?

    enum CodingKeys: String, CodingKey {
        case id = "category_id"
        case name = "category_name"
        case parentID = "parent_id"
    }

    init(id: String, name: String, parentID: String? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            self.id = s
        } else {
            let n = try c.decode(Int.self, forKey: .id)
            self.id = String(n)
        }
        self.name = try c.decode(String.self, forKey: .name)
        self.parentID = try? c.decodeIfPresent(String.self, forKey: .parentID)
    }
}

struct XtreamMovie: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let categoryID: String?
    let streamID: Int
    let icon: String?
    let plot: String?
    let cast: String?
    let director: String?
    let releaseDate: String?
    let rating: String?
    let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case name
        case icon = "stream_icon"
        case categoryID = "category_id"
        case plot
        case cast
        case director
        case releaseDate = "releasedate"
        case rating
        case containerExtension = "container_extension"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.streamID = try c.decode(Int.self, forKey: .streamID)
        self.id = String(streamID)
        self.name = try c.decode(String.self, forKey: .name)
        self.categoryID = try? c.decodeIfPresent(String.self, forKey: .categoryID)
        self.icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        self.plot = try? c.decodeIfPresent(String.self, forKey: .plot)
        self.cast = try? c.decodeIfPresent(String.self, forKey: .cast)
        self.director = try? c.decodeIfPresent(String.self, forKey: .director)
        self.releaseDate = try? c.decodeIfPresent(String.self, forKey: .releaseDate)
        self.rating = try? c.decodeIfPresent(String.self, forKey: .rating)
        self.containerExtension = try? c.decodeIfPresent(String.self, forKey: .containerExtension)
    }
}

struct XtreamSeries: Identifiable, Codable, Hashable {
    let id: String
    let seriesID: Int
    let name: String
    let categoryID: String?
    let cover: String?
    let plot: String?
    let cast: String?
    let director: String?
    let releaseDate: String?
    let rating: String?

    enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
        case name
        case cover
        case categoryID = "category_id"
        case plot
        case cast
        case director
        case releaseDate = "releasedate"
        case rating
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.seriesID = try c.decode(Int.self, forKey: .seriesID)
        self.id = String(seriesID)
        self.name = try c.decode(String.self, forKey: .name)
        self.categoryID = try? c.decodeIfPresent(String.self, forKey: .categoryID)
        self.cover = try? c.decodeIfPresent(String.self, forKey: .cover)
        self.plot = try? c.decodeIfPresent(String.self, forKey: .plot)
        self.cast = try? c.decodeIfPresent(String.self, forKey: .cast)
        self.director = try? c.decodeIfPresent(String.self, forKey: .director)
        self.releaseDate = try? c.decodeIfPresent(String.self, forKey: .releaseDate)
        self.rating = try? c.decodeIfPresent(String.self, forKey: .rating)
    }
}

struct XtreamEpisode: Identifiable, Hashable {
    let id: String
    let episodeID: Int
    let title: String
    let seasonNumber: Int
    let episodeNumber: Int
    let containerExtension: String?
    let plot: String?
    let runtime: String?
    let rating: String?
    let still: String?

    var displayName: String {
        if let runtime, !runtime.isEmpty {
            return "\(episodeNumber). \(title) — \(runtime) min"
        }
        return "\(episodeNumber). \(title)"
    }
}

/// Series detail returned by `get_series_info` — episodes are keyed by season
/// number in the JSON response (`{"1": [...]}`), so we manually decode rather
/// than relying on a single Codable shape.
struct XtreamSeriesInfo: Hashable {
    let seasons: [XtreamSeason]
}

struct XtreamSeason: Identifiable, Hashable {
    var id: Int { number }
    let number: Int
    let episodes: [XtreamEpisode]
}
