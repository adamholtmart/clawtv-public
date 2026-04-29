import Foundation

enum M3UParseError: Error {
    case notAnM3U
    case empty
}

struct M3UParser {
    static func parse(_ text: String) throws -> [Channel] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              first.trimmingCharacters(in: .whitespaces).hasPrefix("#EXTM3U") else {
            throw M3UParseError.notAnM3U
        }

        var channels: [Channel] = []
        var pendingExtinf: String?

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTINF") {
                pendingExtinf = line
                continue
            }
            if line.hasPrefix("#") { continue }

            guard let extinf = pendingExtinf else { continue }
            pendingExtinf = nil

            guard let streamURL = URL(string: line), streamURL.scheme != nil else { continue }

            let meta = parseExtinf(extinf)
            let channel = Channel(
                id: meta.tvgId ?? "\(meta.name)#\(streamURL.absoluteString)",
                name: meta.name,
                logoURL: meta.logo.flatMap { URL(string: $0) },
                streamURL: streamURL,
                groupTitle: meta.group ?? "Uncategorized",
                tvgId: meta.tvgId,
                country: meta.country,
                language: meta.language,
                subtitleURL: meta.subtitles.flatMap { URL(string: $0) },
                catchupSource: meta.catchupSource,
                catchupDays: meta.catchupDays.flatMap { Int($0) }
            )
            channels.append(channel)
        }

        if channels.isEmpty { throw M3UParseError.empty }
        return channels
    }

    private struct ExtinfMeta {
        var name: String
        var logo: String?
        var group: String?
        var tvgId: String?
        var country: String?
        var language: String?
        var subtitles: String?
        var catchupSource: String?
        var catchupDays: String?
    }

    private static func parseExtinf(_ line: String) -> ExtinfMeta {
        let commaIndex = line.lastIndex(of: ",") ?? line.endIndex
        let name = commaIndex < line.endIndex
            ? String(line[line.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
            : "Unnamed"

        let attrsSection = String(line[..<commaIndex])

        var meta = ExtinfMeta(name: name)
        meta.logo = attr(named: "tvg-logo", in: attrsSection)
        meta.group = attr(named: "group-title", in: attrsSection)
        meta.tvgId = attr(named: "tvg-id", in: attrsSection)
        meta.country = attr(named: "tvg-country", in: attrsSection)
        meta.language = attr(named: "tvg-language", in: attrsSection)
        meta.subtitles = attr(named: "tvg-subtitles", in: attrsSection)
            ?? attr(named: "subtitles", in: attrsSection)
        meta.catchupSource = attr(named: "catchup-source", in: attrsSection)
        meta.catchupDays = attr(named: "catchup-days", in: attrsSection)
        return meta
    }

    private static func attr(named key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "\(key)=\"") else { return nil }
        let start = keyRange.upperBound
        guard let end = text.range(of: "\"", range: start..<text.endIndex) else { return nil }
        let value = String(text[start..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
