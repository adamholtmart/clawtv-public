import Foundation
import SwiftUI

struct ScoredChannel: Identifiable, Hashable {
    var id: String { channel.id }
    let channel: Channel
    let score: Int
    let reason: String
}

enum ResolveResult {
    case auto(Channel, confidence: Int, candidates: [ScoredChannel])
    case picker([ScoredChannel])
    case none
}

/// Click-time resolver: EPG channel → ranked M3U stream candidates.
/// If a prior user pick exists for the EPG id, always returns it (saved pick).
/// Otherwise ranks M3U channels by tvg-id / display-name / callsign / token overlap
/// and either auto-plays a confident winner or emits a picker list.
@MainActor
final class ChannelResolver: ObservableObject {
    @Published private(set) var learnedPicks: [String: String] = [:]
    @Published private(set) var recentEPGIds: [String] = []

    private let picksKey = "clawtv.epgPicks.v1"
    private let recentsKey = "clawtv.epgRecents.v1"
    private let recentCap = 20
    private let autoScoreFloor = 85     // top candidate must be at least this strong
    private let autoMargin = 15         // and beat #2 by this many points

    // Hand-tuned M3U tvg-id -> EPG channel id aliases. Key is normalized
    // M3U tvg-id (lowercase alphanumerics). Loaded once from bundle.
    // `nonisolated` so background scoring tasks can read it without hopping to main.
    nonisolated private let tvgIdAliases: [String: String]

    init() {
        if let data = UserDefaults.standard.data(forKey: picksKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            learnedPicks = decoded
        }
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            recentEPGIds = decoded
        }
        tvgIdAliases = Self.loadTvgIdAliases()
    }

    private static func loadTvgIdAliases() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "EPGOverrides", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let aliases = json["aliases"] as? [String: String] else {
            return [:]
        }
        return aliases
    }

    func markOpened(epgId: String) {
        recentEPGIds.removeAll { $0 == epgId }
        recentEPGIds.insert(epgId, at: 0)
        if recentEPGIds.count > recentCap {
            recentEPGIds = Array(recentEPGIds.prefix(recentCap))
        }
        if let data = try? JSONEncoder().encode(recentEPGIds) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    // MARK: - Public API

    func resolve(epg: EPGChannel, in m3u: [Channel]) -> ResolveResult {
        if let pickedId = learnedPicks[epg.id],
           let channel = m3u.first(where: { $0.id == pickedId }) {
            let saved = ScoredChannel(channel: channel, score: 1000,
                                      reason: "Your saved pick")
            return .auto(channel, confidence: 1000, candidates: [saved])
        }
        let ranked = score(epg: epg, against: m3u)
        guard let top = ranked.first else { return .none }
        let trimmed = Array(ranked.prefix(16))
        if top.score >= autoScoreFloor,
           (trimmed.count == 1 || top.score - trimmed[1].score >= autoMargin) {
            return .auto(top.channel, confidence: top.score, candidates: trimmed)
        }
        return .picker(trimmed)
    }

    func candidates(epg: EPGChannel, in m3u: [Channel]) -> [ScoredChannel] {
        Array(score(epg: epg, against: m3u).prefix(24))
    }

    /// Returns the set of EPG channel ids that have at least one likely M3U
    /// match within `m3u`. Cheap pass: tvg-id, alias map, and exact normalized
    /// name. Used to filter the Guide rails to a subset of M3U groups without
    /// running the full scoring matrix.
    /// `nonisolated` so a Task.detached actually runs off-main — `tvgIdAliases`
    /// is `let` and the body mutates no other state.
    nonisolated func reachableEPGIds(epgChannels: [EPGChannel], m3u: [Channel]) -> Set<String> {
        Set(reachableEPGToGroups(epgChannels: epgChannels, m3u: m3u).keys)
    }

    /// For each EPG id with at least one reachable M3U match, returns the set
    /// of M3U `groupTitle` strings the matches came from. Built in a single
    /// pass over the playlist; shares the same matching logic as
    /// `reachableEPGIds`. Used to group the Guide by provider category.
    nonisolated func reachableEPGToGroups(epgChannels: [EPGChannel],
                                          m3u: [Channel]) -> [String: Set<String>] {
        guard !m3u.isEmpty, !epgChannels.isEmpty else { return [:] }

        var epgIdByNorm: [String: String] = [:]
        var epgIdByStrippedNorm: [String: String] = [:]
        var epgIdByName: [String: String] = [:]
        epgIdByNorm.reserveCapacity(epgChannels.count)
        epgIdByName.reserveCapacity(epgChannels.count)
        for c in epgChannels {
            let n = Self.normalize(c.id)
            if !n.isEmpty, epgIdByNorm[n] == nil { epgIdByNorm[n] = c.id }
            let s = Self.normalize(Self.stripCountrySuffix(c.id))
            if !s.isEmpty, epgIdByStrippedNorm[s] == nil { epgIdByStrippedNorm[s] = c.id }
            let nm = Self.normalize(c.displayName)
            if !nm.isEmpty, epgIdByName[nm] == nil { epgIdByName[nm] = c.id }
        }

        var reachable: [String: Set<String>] = [:]
        func record(_ epgId: String, group: String) {
            let g = group.isEmpty ? "Uncategorized" : group
            reachable[epgId, default: []].insert(g)
        }
        for ch in m3u {
            let tvgNorm = Self.normalize(ch.tvgId ?? "")
            if !tvgNorm.isEmpty {
                if let aliasEpg = tvgIdAliases[tvgNorm],
                   let epgId = epgIdByNorm[Self.normalize(aliasEpg)] {
                    record(epgId, group: ch.groupTitle)
                    continue
                }
                if let epgId = epgIdByNorm[tvgNorm] {
                    record(epgId, group: ch.groupTitle)
                    continue
                }
                let stripped = Self.normalize(Self.stripCountrySuffix(ch.tvgId ?? ""))
                if !stripped.isEmpty, let epgId = epgIdByStrippedNorm[stripped] {
                    record(epgId, group: ch.groupTitle)
                    continue
                }
            }
            let nameNorm = Self.normalize(ch.name)
            if !nameNorm.isEmpty, let epgId = epgIdByName[nameNorm] {
                record(epgId, group: ch.groupTitle)
            }
        }
        return reachable
    }

    func learn(epg: EPGChannel, picked: Channel) {
        learnedPicks[epg.id] = picked.id
        persist()
    }

    func forget(epg: EPGChannel) {
        learnedPicks.removeValue(forKey: epg.id)
        persist()
    }

    func hasSavedPick(for epg: EPGChannel) -> Bool {
        learnedPicks[epg.id] != nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(learnedPicks) {
            UserDefaults.standard.set(data, forKey: picksKey)
        }
    }

    // MARK: - Scoring

    private func score(epg: EPGChannel, against m3u: [Channel]) -> [ScoredChannel] {
        let epgIdNorm = Self.normalize(epg.id)
        let epgIdStripped = Self.normalize(Self.stripCountrySuffix(epg.id))
        let epgNameNorm = Self.normalize(epg.displayName)
        let epgCallsign = Self.extractCallsign(epg.displayName)
                        ?? Self.extractCallsign(epg.id)
        let epgTokens = Self.tokens(epg.displayName)

        var out: [ScoredChannel] = []
        out.reserveCapacity(min(m3u.count, 4096))

        for channel in m3u {
            guard var sc = scoreChannel(channel,
                                        epgIdNorm: epgIdNorm,
                                        epgIdStripped: epgIdStripped,
                                        epgNameNorm: epgNameNorm,
                                        epgCallsign: epgCallsign,
                                        epgTokens: epgTokens) else { continue }
            // US-bias nudge
            if Self.looksUS(channel) {
                sc = ScoredChannel(channel: sc.channel,
                                   score: sc.score + 2,
                                   reason: sc.reason)
            } else if Self.looksObviouslyForeign(channel) {
                sc = ScoredChannel(channel: sc.channel,
                                   score: sc.score - 10,
                                   reason: sc.reason)
            }
            out.append(sc)
        }

        out.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            // Tiebreak: prefer shorter channel name (less decorated)
            if a.channel.name.count != b.channel.name.count {
                return a.channel.name.count < b.channel.name.count
            }
            return a.channel.name < b.channel.name
        }
        return out
    }

    private func scoreChannel(_ channel: Channel,
                              epgIdNorm: String,
                              epgIdStripped: String,
                              epgNameNorm: String,
                              epgCallsign: String?,
                              epgTokens: Set<String>) -> ScoredChannel? {
        let chNameNorm = Self.normalize(channel.name)
        let chTvgNorm = Self.normalize(channel.tvgId ?? "")
        let chTvgStripped = Self.normalize(Self.stripCountrySuffix(channel.tvgId ?? ""))

        if !chTvgNorm.isEmpty,
           let aliasEpg = tvgIdAliases[chTvgNorm],
           Self.normalize(aliasEpg) == epgIdNorm {
            return ScoredChannel(channel: channel, score: 100,
                                 reason: "Curated guide alias")
        }
        if !chTvgNorm.isEmpty, chTvgNorm == epgIdNorm {
            return ScoredChannel(channel: channel, score: 100,
                                 reason: "tvg-id exact match")
        }
        if !chTvgStripped.isEmpty, !epgIdStripped.isEmpty,
           chTvgStripped == epgIdStripped {
            return ScoredChannel(channel: channel, score: 95,
                                 reason: "tvg-id match (country suffix ignored)")
        }
        if !chNameNorm.isEmpty, chNameNorm == epgNameNorm {
            return ScoredChannel(channel: channel, score: 90,
                                 reason: "Name matches guide")
        }
        if let cs = epgCallsign {
            if Self.extractCallsign(channel.name) == cs {
                return ScoredChannel(channel: channel, score: 86,
                                     reason: "Callsign \(cs.uppercased()) in name")
            }
            if Self.extractCallsign(channel.tvgId ?? "") == cs {
                return ScoredChannel(channel: channel, score: 80,
                                     reason: "Callsign \(cs.uppercased()) in tvg-id")
            }
        }
        let chTokens = Self.tokens(channel.name)
        if !epgTokens.isEmpty, epgTokens.isSubset(of: chTokens) {
            let extras = max(0, chTokens.count - epgTokens.count)
            // Tight match gets 78; each extra descriptor token (e.g. "east", "alt") drops 3.
            let score = max(55, 78 - extras * 3)
            return ScoredChannel(channel: channel, score: score,
                                 reason: "Contains all guide words")
        }
        if !epgTokens.isEmpty, !chTokens.isEmpty {
            let overlap = epgTokens.intersection(chTokens)
            if overlap.count >= 1 {
                let ratio = Double(overlap.count) / Double(epgTokens.count)
                let score = Int((ratio * 50).rounded()) // up to 50 when fully covered
                if score >= 35 {
                    return ScoredChannel(channel: channel, score: score,
                                         reason: "\(overlap.count) of \(epgTokens.count) words match")
                }
            }
        }
        if !epgNameNorm.isEmpty, chNameNorm.contains(epgNameNorm) {
            return ScoredChannel(channel: channel, score: 30,
                                 reason: "Name contains guide string")
        }
        return nil
    }

    // MARK: - String utilities

    nonisolated static func normalize(_ s: String) -> String {
        let lower = s.lowercased()
        var out = ""
        out.reserveCapacity(lower.count)
        for scalar in lower.unicodeScalars {
            if (scalar.value >= 0x30 && scalar.value <= 0x39) ||
               (scalar.value >= 0x61 && scalar.value <= 0x7A) {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    nonisolated static func stripCountrySuffix(_ s: String) -> String {
        let suffixes = [".us", ".uk", ".ca", ".mx", ".br", ".fr", ".de",
                        ".es", ".it", ".nl", ".se", ".no", ".dk", ".au"]
        var out = s
        for sfx in suffixes where out.lowercased().hasSuffix(sfx) {
            out = String(out.dropLast(sfx.count))
            break
        }
        return out
    }

    static func extractCallsign(_ text: String) -> String? {
        let upper = text.uppercased()
        let strict = "\\b([WK][A-Z]{3,4})\\b"
        if let regex = try? NSRegularExpression(pattern: strict),
           let m = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
           let r = Range(m.range(at: 1), in: upper) {
            return String(upper[r]).lowercased()
        }
        let loose = "([WK][A-Z]{3,4})"
        if let regex = try? NSRegularExpression(pattern: loose),
           let m = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
           let r = Range(m.range(at: 1), in: upper) {
            return String(upper[r]).lowercased()
        }
        return nil
    }

    private static let stopwords: Set<String> = [
        "hd", "uhd", "fhd", "sd", "4k", "1080p", "720p",
        "tv", "channel", "network", "us", "usa", "the",
        "east", "west", "pacific", "atlantic", "eastern", "western"
    ]

    static func tokens(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        var current = ""
        var result: [String] = []
        for scalar in lower.unicodeScalars {
            let isAlnum = (scalar.value >= 0x30 && scalar.value <= 0x39) ||
                          (scalar.value >= 0x61 && scalar.value <= 0x7A)
            if isAlnum {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return Set(result.filter { $0.count >= 2 && !stopwords.contains($0) })
    }

    private static func looksUS(_ channel: Channel) -> Bool {
        if let country = channel.country?.lowercased(),
           country.contains("us") || country.contains("united states") {
            return true
        }
        let group = channel.groupTitle.lowercased()
        return group.contains("united states") || group.contains("usa") ||
               group.contains("us -") || group.hasPrefix("us ")
    }

    private static func looksObviouslyForeign(_ channel: Channel) -> Bool {
        let group = channel.groupTitle.lowercased()
        let hints = ["united kingdom", "germany", "france", "spain", "italy",
                     "india", "pakistan", "arabic", "latino", "mexico", "brazil",
                     "canada", "russia", "poland", "turkey", "greece", "japan",
                     "china", "korea", "portugal", "netherlands"]
        return hints.contains { group.contains($0) }
    }
}
