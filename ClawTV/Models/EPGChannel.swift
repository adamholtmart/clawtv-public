import Foundation

struct EPGChannel: Identifiable, Hashable, Codable {
    let id: String            // XMLTV <channel id="..."> — e.g. "abcwkbwbuffalony.us"
    let displayName: String   // First <display-name>
    let logoURL: URL?         // <icon src="..."> if present

    init(id: String, displayName: String, logoURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.logoURL = logoURL
    }
}
