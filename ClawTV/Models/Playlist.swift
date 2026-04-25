import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var sourceURL: URL
    var addedAt: Date

    init(id: UUID = UUID(), name: String, sourceURL: URL, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.addedAt = addedAt
    }
}
