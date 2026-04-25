import Foundation
import SwiftUI

@MainActor
final class EPGService: ObservableObject {
    // EPG-first (source of truth for the Guide grid)
    @Published private(set) var epgChannels: [EPGChannel] = []
    @Published private(set) var programmesByEPGId: [String: [EPGProgramme]] = [:]

    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingProgrammes = false
    @Published private(set) var hasLoadedProgrammes = false
    @Published private(set) var lastRefresh: Date?

    /// Latched once the Guide has become ready for the first time. Subsequent
    /// background reloads (e.g. after a picker-pick changes the curated set)
    /// must not flip the Guide tab back to its loading placeholder.
    @Published private(set) var hasEverBeenReady = false

    /// True once the Guide can be rendered without blocking:
    /// channels are hydrated, no download/parse in flight, and at least one
    /// programme batch has landed. Used to gate the Guide tab. Latches true
    /// to prevent mid-session view swaps when background reloads run.
    var isGuideReady: Bool {
        if hasEverBeenReady { return true }
        return !isLoading && !isLoadingProgrammes && !epgChannels.isEmpty && hasLoadedProgrammes
    }
    @Published var errorMessage: String?
    @Published var epgURL: String {
        didSet {
            UserDefaults.standard.set(epgURL, forKey: epgURLKey)
        }
    }

    // Legacy M3U → EPG index for ChannelCard / PlayerView enrichment.
    @Published private(set) var index = ChannelEPGIndex()

    private let epgURLKey = "clawtv.epgURL.v1"
    private let lastRefreshKey = "clawtv.epgLastRefresh.v1"
    private let refreshInterval: TimeInterval = 24 * 3600
    private var loadedProgrammeIds: Set<String> = []
    private var programmeLoadTask: Task<Void, Never>?

    init() {
        self.epgURL = UserDefaults.standard.string(forKey: epgURLKey) ?? ""
        if let ts = UserDefaults.standard.object(forKey: lastRefreshKey) as? Date {
            self.lastRefresh = ts
        }
        // Hydrate channel list synchronously from disk — no network, no XML parse.
        if let cached = try? Self.readChannelIndex() {
            self.epgChannels = cached
        }
    }

    // MARK: - EPG-first queries

    func programmes(epgId: String, from start: Date, to end: Date) -> [EPGProgramme] {
        (programmesByEPGId[epgId] ?? []).filter { $0.stop > start && $0.start < end }
    }

    func currentProgramme(epgId: String) -> EPGProgramme? {
        programmesByEPGId[epgId]?.first { $0.isLive }
    }

    func upcoming(epgId: String, limit: Int = 6) -> [EPGProgramme] {
        let now = Date()
        return Array((programmesByEPGId[epgId] ?? []).filter { $0.stop > now }.prefix(limit))
    }

    // MARK: - Legacy (M3U channel based) queries

    func currentProgramme(for channel: Channel) -> EPGProgramme? {
        guard let epgId = index.epgId(for: channel) else { return nil }
        return currentProgramme(epgId: epgId)
    }

    func upcoming(for channel: Channel, limit: Int = 6) -> [EPGProgramme] {
        guard let epgId = index.epgId(for: channel) else { return [] }
        return upcoming(epgId: epgId, limit: limit)
    }

    // MARK: - Refresh

    /// Startup path: do nothing if channels are hydrated and the cache is fresh.
    /// Never blocks; any actual work runs on a background task.
    func refreshIfStale() async {
        let cacheExists = (try? cacheFileURL()).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let fresh = lastRefresh.map { Date().timeIntervalSince($0) < refreshInterval } ?? false
        if !epgChannels.isEmpty, cacheExists, fresh { return }
        await refresh()
    }

    func refresh() async {
        let trimmed = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else {
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let cacheURL = try cacheFileURL()
            try await downloadToDisk(from: url, destination: cacheURL)

            // Pass 1: channel universe only (aborts at first <programme>, fast, low memory).
            let universe = try await Task.detached(priority: .background) {
                try XMLTVParser.parseChannels(fileURL: cacheURL)
            }.value
            let channels = Self.buildEPGChannels(universe: universe)
            self.epgChannels = channels
            // Persist so next launch hydrates instantly.
            try? Self.writeChannelIndex(channels)

            // Invalidate old programme data; callers re-request via loadProgrammes(for:).
            self.programmesByEPGId = [:]
            self.loadedProgrammeIds = []

            self.lastRefresh = Date()
            UserDefaults.standard.set(self.lastRefresh, forKey: lastRefreshKey)
        } catch {
            errorMessage = "EPG load failed: \(error.localizedDescription)"
        }
    }

    /// Load programmes for a set of EPG ids, in small chunks, off the main thread.
    /// Cancels any previous in-flight load so the UI always targets the latest set.
    func loadProgrammes(for ids: Set<String>) async {
        guard !ids.isEmpty else {
            programmeLoadTask?.cancel()
            programmeLoadTask = nil
            programmesByEPGId = [:]
            loadedProgrammeIds = []
            isLoadingProgrammes = false
            hasLoadedProgrammes = false
            return
        }
        if ids == loadedProgrammeIds, !programmesByEPGId.isEmpty { return }

        guard let cacheURL = try? cacheFileURL(),
              FileManager.default.fileExists(atPath: cacheURL.path) else { return }

        programmeLoadTask?.cancel()
        loadedProgrammeIds = ids
        isLoadingProgrammes = true

        // Drop channels that are no longer in the requested set.
        programmesByEPGId = programmesByEPGId.filter { ids.contains($0.key) }

        // One streaming parse of the whole file; coalesce batches off-main and
        // publish a single merged snapshot at most ~1.5s — keeps the SwiftUI
        // invalidation rate bounded so the grid never freezes during parse.
        programmeLoadTask = Task { [weak self] in
            let stream = AsyncStream<[String: [EPGProgramme]]> { continuation in
                let task = Task.detached(priority: .background) {
                    try? XMLTVParser.streamProgrammes(fileURL: cacheURL,
                                                     allowedIds: ids,
                                                     batchSize: 256) { batch in
                        continuation.yield(batch)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            var pending: [String: [EPGProgramme]] = [:]
            var lastFlush = Date.distantPast
            let flushInterval: TimeInterval = 1.5
            for await batch in stream {
                if Task.isCancelled { break }
                for (channel, list) in batch {
                    pending[channel] = list
                }
                if Date().timeIntervalSince(lastFlush) >= flushInterval {
                    let snapshot = pending
                    pending.removeAll(keepingCapacity: true)
                    lastFlush = Date()
                    let sorted = await Task.detached(priority: .background) { () -> [String: [EPGProgramme]] in
                        var out: [String: [EPGProgramme]] = [:]
                        out.reserveCapacity(snapshot.count)
                        for (channel, list) in snapshot {
                            out[channel] = list.sorted { $0.start < $1.start }
                        }
                        return out
                    }.value
                    if Task.isCancelled { break }
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        for (channel, list) in sorted {
                            self.programmesByEPGId[channel] = list
                        }
                    }
                }
            }
            // Final flush — push whatever's left after the parse finishes.
            if !pending.isEmpty {
                let snapshot = pending
                let sorted = await Task.detached(priority: .background) { () -> [String: [EPGProgramme]] in
                    var out: [String: [EPGProgramme]] = [:]
                    out.reserveCapacity(snapshot.count)
                    for (channel, list) in snapshot {
                        out[channel] = list.sorted { $0.start < $1.start }
                    }
                    return out
                }.value
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    for (channel, list) in sorted {
                        self.programmesByEPGId[channel] = list
                    }
                }
            }
            await MainActor.run { [weak self] in
                self?.isLoadingProgrammes = false
                self?.hasLoadedProgrammes = true
                self?.hasEverBeenReady = true
            }
        }
    }

    /// Rebuild the legacy M3U→EPG index against the current universe.
    /// Safe to call whenever the PlaylistStore channel list changes.
    func rebuildM3UIndex(from channels: [Channel]) async {
        let ids = Set(epgChannels.map(\.id))
        guard !ids.isEmpty else {
            await index.rebuild(channels: channels, epgIds: [], epgDisplayNames: [:])
            return
        }
        let names = Dictionary(uniqueKeysWithValues: epgChannels.map { ($0.id, $0.displayName) })
        await index.rebuild(channels: channels, epgIds: ids, epgDisplayNames: names)
    }

    // MARK: - Helpers

    private static func buildEPGChannels(universe: XMLTVChannelUniverse) -> [EPGChannel] {
        var out: [EPGChannel] = []
        out.reserveCapacity(universe.ids.count)
        for id in universe.ids {
            let name = universe.displayNames[id] ?? id
            let icon = universe.icons[id].flatMap(URL.init(string:))
            out.append(EPGChannel(id: id, displayName: name, logoURL: icon))
        }
        out.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return out
    }

    private func cacheFileURL() throws -> URL {
        let dir = try Self.cacheDir()
        return dir.appendingPathComponent("guide.xml")
    }

    private static func channelIndexURL() throws -> URL {
        try cacheDir().appendingPathComponent("channels.json")
    }

    private static func cacheDir() throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("epg", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func readChannelIndex() throws -> [EPGChannel]? {
        let url = try channelIndexURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([EPGChannel].self, from: data)
    }

    private static func writeChannelIndex(_ channels: [EPGChannel]) throws {
        let url = try channelIndexURL()
        let data = try JSONEncoder().encode(channels)
        try data.write(to: url, options: .atomic)
    }

    private func downloadToDisk(from url: URL, destination: URL) async throws {
        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "EPG", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tmp, to: destination)
    }
}

// MARK: - XMLTV Parser

struct XMLTVChannelUniverse {
    let ids: Set<String>
    let displayNames: [String: String]
    let icons: [String: String]
}

enum XMLTVParser {
    /// Pass 1: read only `<channel>` elements and abort at the first `<programme>`.
    /// Keeps memory bounded regardless of total programme count in the file.
    static func parseChannels(fileURL: URL) throws -> XMLTVChannelUniverse {
        guard let stream = InputStream(url: fileURL) else {
            throw NSError(domain: "EPG", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to open EPG file"])
        }
        let parser = XMLParser(stream: stream)
        let delegate = XMLTVChannelDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        // Intentional abort once we see the first <programme>; treat that as success.
        if !parser.parse(), !delegate.aborted, let err = parser.parserError {
            throw err
        }
        return XMLTVChannelUniverse(ids: delegate.ids,
                                    displayNames: delegate.displayNames,
                                    icons: delegate.icons)
    }

    /// Pass 2: stream `<programme>` elements, retaining only those whose channel is
    /// in `allowedIds` and which overlap a forward-looking window.
    static func parseProgrammes(fileURL: URL,
                                allowedIds: Set<String>) throws -> [String: [EPGProgramme]] {
        guard let stream = InputStream(url: fileURL) else {
            throw NSError(domain: "EPG", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to open EPG file"])
        }
        let parser = XMLParser(stream: stream)
        let delegate = XMLTVProgrammeDelegate(allowedIds: allowedIds, batchSize: 0, onBatch: nil)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        if !parser.parse(), let err = parser.parserError {
            throw err
        }
        var sorted: [String: [EPGProgramme]] = [:]
        sorted.reserveCapacity(delegate.programmes.count)
        for (channel, list) in delegate.programmes {
            sorted[channel] = list.sorted { $0.start < $1.start }
        }
        return sorted
    }

    /// Streaming variant: invokes `onBatch` every `batchSize` programmes with the
    /// partial results accumulated so far for channels touched in this batch.
    /// Lets callers surface progress to the UI without waiting for the full file.
    static func streamProgrammes(fileURL: URL,
                                 allowedIds: Set<String>,
                                 batchSize: Int,
                                 onBatch: @escaping ([String: [EPGProgramme]]) -> Void) throws {
        guard let stream = InputStream(url: fileURL) else {
            throw NSError(domain: "EPG", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to open EPG file"])
        }
        let parser = XMLParser(stream: stream)
        let delegate = XMLTVProgrammeDelegate(allowedIds: allowedIds,
                                              batchSize: batchSize,
                                              onBatch: onBatch)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        let ok = parser.parse()
        delegate.flushTail()
        if !ok, let err = parser.parserError {
            throw err
        }
    }
}

private let xmltvDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMddHHmmss Z"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()

private func parseXMLTVDate(_ str: String?) -> Date? {
    guard let s = str?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
    return xmltvDateFormatter.date(from: s)
}

private final class XMLTVChannelDelegate: NSObject, XMLParserDelegate {
    var ids: Set<String> = []
    var displayNames: [String: String] = [:]
    var icons: [String: String] = [:]
    var aborted = false

    private var inChannel = false
    private var currentChannelId: String?
    private var currentDisplayName: String = ""
    private var captureDisplayName = false

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "programme" {
            aborted = true
            parser.abortParsing()
            return
        }
        if elementName == "channel" {
            inChannel = true
            currentChannelId = attributeDict["id"]
            currentDisplayName = ""
        } else if elementName == "display-name", inChannel {
            captureDisplayName = displayNames[currentChannelId ?? ""] == nil
        } else if elementName == "icon", inChannel,
                  let id = currentChannelId, icons[id] == nil,
                  let src = attributeDict["src"], !src.isEmpty {
            icons[id] = src
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inChannel, captureDisplayName {
            currentDisplayName += string
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "channel" {
            if let id = currentChannelId, !id.isEmpty {
                ids.insert(id)
                let trimmed = currentDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, displayNames[id] == nil {
                    displayNames[id] = trimmed
                }
            }
            inChannel = false
            currentChannelId = nil
            currentDisplayName = ""
        } else if elementName == "display-name" {
            captureDisplayName = false
        }
    }
}

private final class XMLTVProgrammeDelegate: NSObject, XMLParserDelegate {
    var programmes: [String: [EPGProgramme]] = [:]
    var pendingBatch: [String: [EPGProgramme]] = [:]
    var aborted = false
    weak var parser: XMLParser?

    private let allowedIds: Set<String>
    private let windowStart: Date = Date().addingTimeInterval(-2 * 3600)
    private let windowEnd: Date = Date().addingTimeInterval(48 * 3600)
    private let batchSize: Int
    private let onBatch: (([String: [EPGProgramme]]) -> Void)?
    private var sinceFlush = 0

    private var inProgramme = false
    private var keepCurrent = false
    private var currentProgChannel: String?
    private var currentStart: Date?
    private var currentStop: Date?
    private var currentTitle: String = ""
    private var currentDesc: String = ""
    private var currentElement: String?

    init(allowedIds: Set<String>,
         batchSize: Int,
         onBatch: (([String: [EPGProgramme]]) -> Void)?) {
        self.allowedIds = allowedIds
        self.batchSize = batchSize
        self.onBatch = onBatch
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        guard elementName == "programme" else { return }
        inProgramme = true
        currentTitle = ""
        currentDesc = ""
        guard let ch = attributeDict["channel"], allowedIds.contains(ch) else {
            currentProgChannel = nil
            keepCurrent = false
            return
        }
        currentProgChannel = ch
        currentStart = parseXMLTVDate(attributeDict["start"])
        currentStop = parseXMLTVDate(attributeDict["stop"])
        if let start = currentStart, let stop = currentStop,
           stop > windowStart && start < windowEnd {
            keepCurrent = true
        } else {
            keepCurrent = false
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inProgramme, keepCurrent else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "desc":  currentDesc += string
        default:      break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "programme" {
            if keepCurrent,
               let channelId = currentProgChannel,
               let start = currentStart,
               let stop = currentStop {
                let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let desc = currentDesc.trimmingCharacters(in: .whitespacesAndNewlines)
                let prog = EPGProgramme(channelId: channelId,
                                        start: start,
                                        stop: stop,
                                        title: title.isEmpty ? "—" : title,
                                        desc: desc.isEmpty ? nil : desc)
                programmes[channelId, default: []].append(prog)
                if batchSize > 0, onBatch != nil {
                    pendingBatch[channelId, default: []].append(prog)
                    sinceFlush += 1
                    if sinceFlush >= batchSize {
                        flushBatch()
                    }
                }
            }
            inProgramme = false
            keepCurrent = false
            currentProgChannel = nil
            currentStart = nil
            currentStop = nil
        }
        currentElement = nil
    }

    func flushTail() {
        flushBatch()
    }

    private func flushBatch() {
        guard let onBatch, !pendingBatch.isEmpty else { return }
        let touched = Set(pendingBatch.keys)
        pendingBatch.removeAll(keepingCapacity: true)
        sinceFlush = 0
        var snapshot: [String: [EPGProgramme]] = [:]
        for ch in touched {
            snapshot[ch] = programmes[ch]
        }
        onBatch(snapshot)
    }
}
