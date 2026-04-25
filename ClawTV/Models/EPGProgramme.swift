import Foundation

struct EPGProgramme: Identifiable, Hashable {
    let id = UUID()
    let channelId: String
    let start: Date
    let stop: Date
    let title: String
    let desc: String?

    var isLive: Bool {
        let now = Date()
        return now >= start && now < stop
    }

    var progress: Double {
        let total = stop.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }
}
