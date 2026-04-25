import Foundation

/// Selects the curated EPG channel set that powers the Guide view.
/// Priority (highest first):
///   1. Learned picks (user has confirmed an EPG → M3U match)
///   2. Recently watched EPG channels
///   3. Major US networks (broadcast, cable, sports, premium)
///   4. Remaining EPG channels alphabetically
enum GuideCurator {
    static let majorNetworkTokens: [String] = [
        // Broadcast
        "nbc", "cbs", "abc", "fox", "pbs", "cw",
        // Cable news / talk
        "cnn", "msnbc", "bloomberg", "cnbc", "bbc", "c-span", "newsmax",
        // Sports
        "espn", "espn2", "espnu", "nfl network", "nba tv",
        "mlb network", "nhl network", "golf channel", "fs1", "fs2",
        "tennis channel", "sec network", "big ten", "acc network",
        // General entertainment
        "tnt", "tbs", "usa network", "fx", "fxx", "amc", "syfy",
        "bravo", "hgtv", "food network", "tlc", "discovery", "history",
        "a&e", "lifetime", "paramount", "nat geo", "national geographic",
        "animal planet", "travel", "investigation discovery",
        // Premium
        "hbo", "showtime", "starz", "cinemax", "mgm+", "epix",
        // Kids
        "disney", "cartoon network", "nickelodeon", "nick jr", "boomerang",
        "pbs kids", "disney jr", "disney xd",
        // Music / other
        "mtv", "vh1", "bet", "cmt", "comedy central", "adult swim"
    ]

    static func curate(epgChannels: [EPGChannel],
                       learnedEPGIds: Set<String>,
                       recentEPGIds: [String],
                       cap: Int = 160) -> [EPGChannel] {
        var seen = Set<String>()
        var out: [EPGChannel] = []

        func add(_ c: EPGChannel) {
            guard seen.insert(c.id).inserted else { return }
            out.append(c)
        }

        let byId = Dictionary(uniqueKeysWithValues: epgChannels.map { ($0.id, $0) })

        // 1. Learned picks
        let learned = epgChannels
            .filter { learnedEPGIds.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        learned.forEach(add)

        // 2. Recently opened (order preserved)
        for id in recentEPGIds {
            if let c = byId[id] { add(c) }
        }

        // 3. Major networks — pick the shortest-name channel for each token (avoid "... HD East")
        for token in majorNetworkTokens where out.count < cap {
            let t = token.trimmingCharacters(in: .whitespaces).lowercased()
            guard !t.isEmpty else { continue }
            let candidates = epgChannels
                .filter { !seen.contains($0.id) && $0.displayName.lowercased().contains(t) }
                .sorted { a, b in
                    if a.displayName.count != b.displayName.count {
                        return a.displayName.count < b.displayName.count
                    }
                    return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
                }
            if let best = candidates.first { add(best) }
        }

        // 4. Everything else alphabetically
        let remaining = epgChannels
            .filter { !seen.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        for c in remaining where out.count < cap {
            add(c)
        }

        return out
    }
}
