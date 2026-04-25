import Foundation

/// Resolves Channels → EPG tvg-id using three tiers:
///   1. Exact tvg-id match (channel attribute equals an EPG channel id)
///   2. Manual override map (seed JSON for known-problem callsigns)
///   3. Callsign / normalized-name fuzzy match against EPG channel ids + display names
@MainActor
final class ChannelEPGIndex: ObservableObject {
    @Published private(set) var lastBuild: Date?
    @Published private(set) var matched: Int = 0
    @Published private(set) var total: Int = 0

    private var resolvedIds: [String: String] = [:]
    private var overrides: [String: String] = [:]

    init() {
        self.overrides = Self.loadOverrides()
    }

    /// Returns the resolved EPG channel id for a Channel, or nil if no match.
    func epgId(for channel: Channel) -> String? {
        resolvedIds[channel.id]
    }

    /// Rebuild the index against the current EPG universe. Off-main; UI-friendly.
    /// Replaces O(channels × epgIds) prefix/contains scans with prebuilt lookup tables.
    func rebuild(channels: [Channel],
                 epgIds: Set<String>,
                 epgDisplayNames: [String: String]) async {
        let overridesSnapshot = self.overrides
        let resolved = await Task.detached(priority: .background) {
            Self.computeResolved(channels: channels,
                                 epgIds: epgIds,
                                 epgDisplayNames: epgDisplayNames,
                                 overrides: overridesSnapshot)
        }.value
        self.resolvedIds = resolved
        self.matched = resolved.count
        self.total = channels.count
        self.lastBuild = Date()
    }

    nonisolated private static func computeResolved(channels: [Channel],
                                                    epgIds: Set<String>,
                                                    epgDisplayNames: [String: String],
                                                    overrides: [String: String]) -> [String: String] {
        let normalizedIdMap = normalizedIndex(epgIds)

        // Display-name map (normalized name → epg id), plus a name-normalized lookup.
        var displayNameToId: [String: String] = [:]
        displayNameToId.reserveCapacity(epgDisplayNames.count)
        for (id, name) in epgDisplayNames {
            displayNameToId[normalize(name)] = id
        }

        // Callsign bucket: every epg id (and its display name) that contains a
        // 4-letter US callsign gets registered under that callsign. One-shot build.
        var callsignToId: [String: String] = [:]
        for id in epgIds {
            if let cs = extractCallsign(id) {
                callsignToId[cs] = id
            }
        }
        for (id, name) in epgDisplayNames {
            if let cs = extractCallsign(name), callsignToId[cs] == nil {
                callsignToId[cs] = id
            }
        }

        // Sorted normalized ids for prefix probes: binary-search friendly.
        let sortedNormalizedIds = normalizedIdMap.keys.sorted()

        var resolved: [String: String] = [:]
        resolved.reserveCapacity(channels.count)

        for channel in channels {
            if let tvg = channel.tvgId?.trimmingCharacters(in: .whitespaces),
               !tvg.isEmpty,
               epgIds.contains(tvg) {
                resolved[channel.id] = tvg
                continue
            }

            let nameKey = normalize(channel.name)
            if let override = overrides[nameKey], epgIds.contains(override) {
                resolved[channel.id] = override
                continue
            }

            if let tvg = channel.tvgId {
                let tvgStripped = normalize(stripCountrySuffix(tvg))
                if !tvgStripped.isEmpty {
                    if let override = overrides[tvgStripped], epgIds.contains(override) {
                        resolved[channel.id] = override
                        continue
                    }
                    if let hit = prefixLookup(tvgStripped, in: sortedNormalizedIds) {
                        resolved[channel.id] = normalizedIdMap[hit]
                        continue
                    }
                }
            }

            if let hit = displayNameToId[nameKey] {
                resolved[channel.id] = hit
                continue
            }

            let callsign = extractCallsign(channel.name)
                ?? channel.tvgId.flatMap { extractCallsign($0) }
            if let cs = callsign, let hit = callsignToId[cs] {
                resolved[channel.id] = hit
                continue
            }

            if let hit = normalizedIdMap[nameKey] {
                resolved[channel.id] = hit
            }
        }
        return resolved
    }

    /// Binary-search-assisted prefix lookup: first sorted key that starts with `prefix`.
    nonisolated private static func prefixLookup(_ prefix: String, in sortedKeys: [String]) -> String? {
        guard !prefix.isEmpty else { return nil }
        var lo = 0
        var hi = sortedKeys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedKeys[mid] < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        guard lo < sortedKeys.count else { return nil }
        let candidate = sortedKeys[lo]
        return candidate.hasPrefix(prefix) ? candidate : nil
    }

    // MARK: - Normalization

    nonisolated static func normalize(_ s: String) -> String {
        let lower = s.lowercased()
        var out = ""
        out.reserveCapacity(lower.count)
        for scalar in lower.unicodeScalars {
            if (scalar.value >= 0x30 && scalar.value <= 0x39) ||   // 0-9
               (scalar.value >= 0x61 && scalar.value <= 0x7A) {    // a-z
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Extract a 4-letter US broadcast callsign (W*** or K***) from a channel name or tvg-id.
    nonisolated static func extractCallsign(_ text: String) -> String? {
        // Try strict word-bounded match first
        let upper = text.uppercased()
        let strict = "\\b([WK][A-Z]{3,4})\\b"
        if let regex = try? NSRegularExpression(pattern: strict),
           let m = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
           let r = Range(m.range(at: 1), in: upper) {
            return String(upper[r]).lowercased()
        }
        // Fallback: embedded in alphanum blob (e.g. tvg-id "abcwkbw.us")
        let loose = "([WK][A-Z]{3,4})"
        if let regex = try? NSRegularExpression(pattern: loose),
           let m = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
           let r = Range(m.range(at: 1), in: upper) {
            return String(upper[r]).lowercased()
        }
        return nil
    }

    /// Strip trailing country suffix (".us", ".uk", ".ca", etc.) from a tvg-id.
    nonisolated static func stripCountrySuffix(_ s: String) -> String {
        let suffixes = [".us", ".uk", ".ca", ".mx", ".br", ".fr", ".de", ".es", ".it"]
        var out = s
        for sfx in suffixes where out.lowercased().hasSuffix(sfx) {
            out = String(out.dropLast(sfx.count))
            break
        }
        return out
    }

    nonisolated private static func normalizedIndex(_ values: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for v in values {
            out[normalize(v)] = v
        }
        return out
    }

    nonisolated private static func normalizedIndex(_ values: Set<String>) -> [String: String] {
        normalizedIndex(Array(values))
    }

    // MARK: - Overrides

    /// Seed map of normalized channel names → EPG channel ids.
    /// Covers the Buffalo locals that don't match by tvg-id.
    /// Users can extend via on-disk JSON at `epg_overrides.json` in Documents.
    private static func loadOverrides() -> [String: String] {
        var map: [String: String] = [:]
        // Buffalo-area locals
        map["nbc2wgrz"] = "nbcwgrzbuffalony.us"
        map["nbcwgrz"] = "nbcwgrzbuffalony.us"
        map["wgrz"] = "nbcwgrzbuffalony.us"
        map["wgrzbuffalo"] = "nbcwgrzbuffalony.us"
        map["cbs4wivb"] = "cbswivbbuffalony.us"
        map["cbswivb"] = "cbswivbbuffalony.us"
        map["wivb"] = "cbswivbbuffalony.us"
        map["abc7wkbw"] = "abcwkbwbuffalony.us"
        map["abcwkbw"] = "abcwkbwbuffalony.us"
        map["wkbw"] = "abcwkbwbuffalony.us"
        map["fox29wutv"] = "foxwutvbuffalony.us"
        map["foxwutv"] = "foxwutvbuffalony.us"
        map["wutv"] = "foxwutvbuffalony.us"
        map["pbswned"] = "pbswnedbuffalony.us"
        map["wned"] = "pbswnedbuffalony.us"
        map["cw23wnlo"] = "cwwnlobuffalony.us"

        // Load Documents/epg_overrides.json if present (user-editable)
        let fm = FileManager.default
        if let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: false) {
            let url = docs.appendingPathComponent("epg_overrides.json")
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                for (k, v) in decoded {
                    map[normalize(k)] = v
                }
            }
        }
        return map
    }
}
