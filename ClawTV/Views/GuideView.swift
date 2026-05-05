import SwiftUI

struct GuideView: View {
    @EnvironmentObject var store: PlaylistStore
    @EnvironmentObject var epg: EPGService
    @EnvironmentObject var resolver: ChannelResolver
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif
    @State private var anchor: Date = Self.defaultAnchor()
    @State private var pickerRequest: PickerRequest?
    @State private var allowedEPGIds: Set<String> = []
    @State private var epgToGroups: [String: Set<String>] = [:]
    @State private var lastFilterKey: String = ""
    @State private var curated: [EPGChannel] = []
    @State private var eligibleCount: Int = 0
    @State private var sections: [GuideSection] = []
    @State private var lastCurateKey: String = ""
    @State private var isCurating: Bool = false
    @State private var collapsedGroups: Set<String> = Self.loadCollapsedGroups()

    private static let collapsedGroupsKey = "clawtv.guideCollapsedGroups.v1"

    private let rowHeight: CGFloat = 96
    private let channelColumnWidth: CGFloat = 280
    private let slotWidth: CGFloat = 280     // 280pt per 30 min → 9.33pt/min
    private let slotMinutes: Int = 30
    private let hoursShown: Int = 8

    private var pxPerMinute: CGFloat { slotWidth / CGFloat(slotMinutes) }
    private var windowEnd: Date { anchor.addingTimeInterval(TimeInterval(hoursShown * 3600)) }

    private var filterKey: String {
        "\(store.channels.count)|\(epg.epgChannels.count)"
    }

    private var curateKey: String {
        "\(allowedEPGIds.count)|\(epg.epgChannels.count)|\(resolver.learnedPicks.count)|\(resolver.recentEPGIds.count)|\(store.favoriteGroups.count)"
    }

    private var isBusy: Bool {
        epg.isLoading || epg.isLoadingProgrammes || isCurating
    }

    private var busyLabel: String {
        if epg.isLoading { return "Downloading guide" }
        if isCurating { return "Preparing guide" }
        if epg.isLoadingProgrammes { return "Loading schedule" }
        return ""
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
                footerStats
            }
            .padding(.vertical, 24)
            .navigationTitle("Guide")
            .overlay(alignment: .topTrailing) { busyBadge }
        }
        .task {
            if epg.epgChannels.isEmpty && !epg.isLoading {
                await epg.refreshIfStale()
            }
        }
        .task(id: filterKey) {
            await recomputeAllowedEPGIds()
        }
        .task(id: curateKey) {
            await recomputeCurated()
        }
        .sheet(item: $pickerRequest) { req in
            ChannelPickerSheet(
                epg: req.epg,
                candidates: req.candidates,
                onPick: { channel, remember in
                    handlePick(epg: req.epg, channel: channel, remember: remember)
                },
                onDismiss: { pickerRequest = nil }
            )
            .environmentObject(store)
            .environmentObject(resolver)
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        if epg.epgChannels.isEmpty && epg.isLoading {
            emptyState("Loading guide data…", system: "hourglass")
        } else if epg.epgChannels.isEmpty {
            emptyState("No guide data yet.", system: "tv.slash")
        } else if sections.isEmpty {
            emptyState("No playlist channels matched the guide yet.",
                       system: "tv.slash")
        } else {
            #if os(iOS)
            if hSizeClass == .compact {
                guideList
            } else {
                guideGrid
            }
            #else
            guideGrid
            #endif
        }
    }

    private func recomputeAllowedEPGIds() async {
        let key = filterKey
        guard key != lastFilterKey else { return }
        await MainActor.run { isCurating = true }
        let allowedM3U = store.channels
        let epgChannels = epg.epgChannels
        let res = resolver
        let map = await Task.detached(priority: .userInitiated) {
            await res.reachableEPGToGroups(epgChannels: epgChannels, m3u: allowedM3U)
        }.value
        await MainActor.run {
            epgToGroups = map
            allowedEPGIds = Set(map.keys)
            lastFilterKey = key
            isCurating = false
        }
    }

    private func recomputeCurated() async {
        let key = curateKey
        guard key != lastCurateKey else { return }
        await MainActor.run { isCurating = true }
        let allowed = allowedEPGIds
        let all = epg.epgChannels
        let learned = Set(resolver.learnedPicks.keys)
        let recent = resolver.recentEPGIds
        let groupsMap = epgToGroups
        let favGroups = store.favoriteGroups
        let result = await Task.detached(priority: .userInitiated) { () -> ([EPGChannel], Int, [GuideSection]) in
            let eligible = allowed.isEmpty ? [] : all.filter { allowed.contains($0.id) }
            let curated = GuideCurator.curate(epgChannels: eligible,
                                              learnedEPGIds: learned,
                                              recentEPGIds: recent,
                                              cap: 500)
            let curatedIds = Set(curated.map(\.id))
            let orderIndex = Dictionary(uniqueKeysWithValues:
                curated.enumerated().map { ($0.element.id, $0.offset) })

            // Bucket each curated channel into every group it's reachable through
            // so multi-group channels (e.g. HBO in Premium *and* Movies) appear
            // in each section.
            var buckets: [String: [EPGChannel]] = [:]
            for channel in curated {
                let groups = groupsMap[channel.id] ?? ["Uncategorized"]
                for group in groups {
                    buckets[group, default: []].append(channel)
                }
            }
            for key in buckets.keys {
                buckets[key]?.sort {
                    (orderIndex[$0.id] ?? Int.max) < (orderIndex[$1.id] ?? Int.max)
                }
            }

            let (favNames, restNames) = buckets.keys.reduce(
                into: ([String](), [String]())
            ) { acc, name in
                if favGroups.contains(name) { acc.0.append(name) } else { acc.1.append(name) }
            }
            let sortedFav = favNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let sortedRest = restNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let ordered = (sortedFav + sortedRest).compactMap { name -> GuideSection? in
                guard let channels = buckets[name], !channels.isEmpty else { return nil }
                return GuideSection(name: name,
                                    channels: channels,
                                    isFavorite: favGroups.contains(name))
            }
            // Filter curated to just what actually landed in sections (same
            // universe, but the eligibleCount should match the channel pool).
            let matchedCount = curated.filter { curatedIds.contains($0.id) }.count
            return (curated, matchedCount, ordered)
        }.value
        await MainActor.run {
            curated = result.0
            eligibleCount = result.1
            sections = result.2
            lastCurateKey = key
            isCurating = false
        }
        // Kick off programme load for the freshly curated set, off the render path.
        let ids = Set(result.0.map(\.id))
        if !ids.isEmpty {
            await epg.loadProgrammes(for: ids)
        }
    }

    private func toggleSection(_ name: String) {
        if collapsedGroups.contains(name) {
            collapsedGroups.remove(name)
        } else {
            collapsedGroups.insert(name)
        }
        persistCollapsedGroups()
    }

    private func persistCollapsedGroups() {
        if let data = try? JSONEncoder().encode(Array(collapsedGroups)) {
            UserDefaults.standard.set(data, forKey: Self.collapsedGroupsKey)
        }
    }

    private static func loadCollapsedGroups() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: collapsedGroupsKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
    }

    private var header: some View {
        HStack(spacing: 24) {
            Button { anchor = Self.roundedHalfHour(Date()) } label: {
                Label("Now", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.bordered)

            Button { anchor = anchor.addingTimeInterval(-3600) } label: {
                Label("-1h", systemImage: "arrow.left")
            }
            .buttonStyle(.bordered)

            Button { anchor = anchor.addingTimeInterval(3600) } label: {
                Label("+1h", systemImage: "arrow.right")
            }
            .buttonStyle(.bordered)

            Spacer()

            Text(headerDateLabel)
                .font(.title3)
                .foregroundStyle(.secondary)

        }
        .padding(.horizontal, Layout.hPad)
    }

    @ViewBuilder
    private var busyBadge: some View {
        if isBusy {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("\(busyLabel)…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.black.opacity(0.55))
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.top, 24)
            .padding(.trailing, Layout.hPad)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: busyLabel)
        }
    }

    @ViewBuilder
    private var footerStats: some View {
        if epg.epgChannels.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                Text("\(sections.count) groups · \(curated.count) channels · \(store.channels.count) streams available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !resolver.learnedPicks.isEmpty {
                    Text("·  \(resolver.learnedPicks.count) saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Layout.hPad)
        }
    }

    private var headerDateLabel: String {
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: anchor)
    }

    // MARK: - Phone list layout

    #if os(iOS)
    private var guideList: some View {
        List {
            ForEach(sections) { section in
                Section {
                    if !collapsedGroups.contains(section.name) {
                        ForEach(section.channels) { channel in
                            channelListRow(for: channel)
                                .listRowBackground(Color.white.opacity(0.04))
                                .listRowSeparatorTint(Color.white.opacity(0.08))
                        }
                    }
                } header: {
                    Button {
                        toggleSection(section.name)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: collapsedGroups.contains(section.name) ? "chevron.right" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if section.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.yellow)
                            }
                            Text(section.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("\(section.channels.count)")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                            Spacer(minLength: 0)
                        }
                        .textCase(nil)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func channelListRow(for channel: EPGChannel) -> some View {
        Button {
            openProgramme(epg: channel)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let logo = channel.logoURL {
                        AsyncImage(url: logo) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFit()
                            default: Image(systemName: "tv.fill").foregroundStyle(.tertiary)
                            }
                        }
                    } else {
                        Image(systemName: "tv.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(channel.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        if resolver.hasSavedPick(for: channel) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                    if let prog = currentOrNextProgramme(for: channel) {
                        HStack(spacing: 5) {
                            if prog.isLive {
                                Circle().fill(Color.red).frame(width: 5, height: 5)
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.red)
                            }
                            Text(prog.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("No schedule")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func currentOrNextProgramme(for channel: EPGChannel) -> EPGProgramme? {
        let progs = programmes(for: channel)
        return progs.first { $0.start <= anchor && $0.stop > anchor }
            ?? progs.min(by: { $0.start < $1.start })
    }
    #endif

    // MARK: - Grid layout

    private var guideGrid: some View {
        // LazyVStack so tvOS only realizes rows currently in view + buffer.
        // Collapsed sections skip their rows entirely, which also keeps the
        // focus engine's working set small.
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                timeHeaderRow
                ForEach(sections) { section in
                    sectionHeader(section)
#if os(tvOS)
                        .focusSection()
#endif
                    if !collapsedGroups.contains(section.name) {
                        ForEach(section.channels) { channel in
                            channelRow(for: channel)
#if os(tvOS)
                                .focusSection()
#endif
                        }
                    }
                }
            }
            .padding(.horizontal, Layout.hPad)
            .padding(.bottom, Layout.vPad)
        }
#if os(tvOS)
        .focusSection()
#endif
    }

    private func sectionHeader(_ section: GuideSection) -> some View {
        let expanded = !collapsedGroups.contains(section.name)
        return Button {
            toggleSection(section.name)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                if section.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.yellow)
                }
                Text(section.name)
                    .font(.system(size: 20, weight: .semibold))
                Text("\(section.channels.count)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 52, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(section.isFavorite
                          ? Color.yellow.opacity(0.08)
                          : Color.white.opacity(0.03))
            )
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.channelCard)
        #endif
        .contextMenu {
            Button {
                store.toggleFavoriteGroup(section.name)
            } label: {
                if section.isFavorite {
                    Label("Unpin from Top", systemImage: "pin.slash")
                } else {
                    Label("Pin to Top", systemImage: "pin")
                }
            }
            Button {
                toggleSection(section.name)
            } label: {
                if collapsedGroups.contains(section.name) {
                    Label("Expand", systemImage: "chevron.down")
                } else {
                    Label("Collapse", systemImage: "chevron.right")
                }
            }
        }
        .padding(.top, 18)
    }

    private var totalProgrammeWidth: CGFloat {
        CGFloat(hoursShown * 60) * pxPerMinute
    }

    private var timeHeaderRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: channelColumnWidth, height: 48, alignment: .leading)
            ForEach(slots, id: \.self) { slotDate in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.timeLabel(slotDate))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
                .frame(width: slotWidth, height: 48, alignment: .leading)
            }
        }
    }

    private func channelRow(for channel: EPGChannel) -> some View {
        let progs = programmes(for: channel)
        return HStack(alignment: .top, spacing: 0) {
            channelCell(channel)
            programmeStrip(channel: channel, progs: progs)
        }
        .frame(height: rowHeight)
        .overlay(alignment: .topLeading) { nowLine() }
    }

    @ViewBuilder
    private func programmeStrip(channel: EPGChannel, progs: [EPGProgramme]) -> some View {
        ZStack(alignment: .topLeading) {
            slotBackground
            if progs.isEmpty {
                emptyProgrammeButton(channel: channel)
            } else {
                programmeRow(channel: channel, progs: progs)
            }
        }
        .frame(width: totalProgrammeWidth, height: rowHeight - 4, alignment: .topLeading)
    }

    private var slotBackground: some View {
        HStack(spacing: 0) {
            ForEach(slots, id: \.self) { _ in
                Rectangle()
                    .fill(Color.white.opacity(0.02))
                    .frame(width: slotWidth, height: rowHeight - 4)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
                    }
            }
        }
    }

    private func programmeRow(channel: EPGChannel, progs: [EPGProgramme]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(layoutItems(for: progs).enumerated()), id: \.offset) { _, item in
                switch item {
                case .gap(let w):
                    Color.clear.frame(width: w, height: rowHeight - 8)
                case .programme(let prog, let w):
                    Button {
                        openProgramme(epg: channel)
                    } label: {
                        ProgrammeCell(programme: prog, isLive: prog.isLive)
                            .frame(width: w, height: rowHeight - 8, alignment: .leading)
                    }
                    #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.channelCard)
        #endif
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func emptyProgrammeButton(channel: EPGChannel) -> some View {
        Button {
            openProgramme(epg: channel)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tv")
                Text("No schedule — tap to find a stream")
                    .font(.system(size: 15))
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight - 12, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))
            )
            .foregroundStyle(.secondary)
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.channelCard)
        #endif
        .padding(.leading, 12)
        .padding(.top, 6)
        .padding(.trailing, 12)
    }

    private enum LayoutItem {
        case gap(CGFloat)
        case programme(EPGProgramme, CGFloat)
    }

    private func layoutItems(for progs: [EPGProgramme]) -> [LayoutItem] {
        let sorted = progs.sorted { $0.start < $1.start }
        var items: [LayoutItem] = []
        var cursorMinutes: CGFloat = 0
        let totalMinutes = CGFloat(hoursShown * 60)
        for prog in sorted {
            let startMin = max(0, CGFloat(prog.start.timeIntervalSince(anchor)) / 60.0)
            let endMin = min(totalMinutes, CGFloat(prog.stop.timeIntervalSince(anchor)) / 60.0)
            guard endMin > cursorMinutes, endMin > startMin else { continue }
            let clampedStart = max(startMin, cursorMinutes)
            if clampedStart > cursorMinutes {
                items.append(.gap((clampedStart - cursorMinutes) * pxPerMinute))
            }
            let width = max(48, (endMin - clampedStart) * pxPerMinute - 4)
            items.append(.programme(prog, width))
            cursorMinutes = endMin
        }
        return items
    }

    private func channelCell(_ channel: EPGChannel) -> some View {
        let hasSaved = resolver.hasSavedPick(for: channel)
        return Button {
            openProgramme(epg: channel)
        } label: {
            HStack(spacing: 12) {
                if let logo = channel.logoURL {
                    AsyncImage(url: logo) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit()
                        default: Image(systemName: "tv.fill").foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 60, height: 60)
                } else {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, height: 60)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(channel.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                        if hasSaved {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green.opacity(0.85))
                        }
                    }
                    Text(channel.id)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(width: channelColumnWidth, height: rowHeight - 4, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))
            )
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.channelCard)
        #endif
    }

    @ViewBuilder
    private func nowLine() -> some View {
        let now = Date()
        if now > anchor, now < windowEnd {
            let x = channelColumnWidth + offset(for: now)
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: rowHeight)
                .offset(x: x, y: 0)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Click handling

    private func openProgramme(epg epgChannel: EPGChannel) {
        resolver.markOpened(epgId: epgChannel.id)
        switch resolver.resolve(epg: epgChannel, in: store.channels) {
        case .auto(let channel, _, _):
            store.openChannel(channel, siblings: [], epgChannelId: epgChannel.id)
        case .picker(let candidates):
            pickerRequest = PickerRequest(epg: epgChannel, candidates: candidates)
        case .none:
            pickerRequest = PickerRequest(epg: epgChannel, candidates: [])
        }
    }

    private func handlePick(epg epgChannel: EPGChannel, channel: Channel, remember: Bool) {
        if remember { resolver.learn(epg: epgChannel, picked: channel) }
        pickerRequest = nil
        // Let the sheet fully dismiss before the fullScreenCover presents —
        // presenting a cover while a sheet is mid-dismiss on tvOS can tear
        // the scene down and bounce the user back to the root tab.
        let captured = channel
        let captured_epg = epgChannel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [store] in
            store.openChannel(captured, siblings: [], epgChannelId: captured_epg.id)
        }
    }

    // MARK: - Slots & geometry

    private var slots: [Date] {
        (0..<hoursShown * (60 / slotMinutes)).map {
            anchor.addingTimeInterval(TimeInterval($0 * slotMinutes * 60))
        }
    }

    private func programmes(for channel: EPGChannel) -> [EPGProgramme] {
        epg.programmes(epgId: channel.id, from: anchor, to: windowEnd)
    }

    private func offset(for date: Date) -> CGFloat {
        max(0, CGFloat(date.timeIntervalSince(anchor)) / 60.0 * pxPerMinute)
    }

    private func width(for prog: EPGProgramme) -> CGFloat {
        let start = max(prog.start, anchor)
        let stop = min(prog.stop, windowEnd)
        let minutes = stop.timeIntervalSince(start) / 60.0
        return max(48, CGFloat(minutes) * pxPerMinute - 4)
    }

    private static func timeLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    private static func roundedHalfHour(_ date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.minute = (comps.minute ?? 0) < 30 ? 0 : 30
        comps.second = 0
        return cal.date(from: comps) ?? date
    }

    private static func defaultAnchor() -> Date { roundedHalfHour(Date()) }

    private func emptyState(_ text: String, system: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: system)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.vertical, 60)
    }
}

private struct PickerRequest: Identifiable {
    let id = UUID()
    let epg: EPGChannel
    let candidates: [ScoredChannel]
}

struct GuideSection: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let channels: [EPGChannel]
    let isFavorite: Bool
}

private struct ProgrammeCell: View {
    let programme: EPGProgramme
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(programme.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                if isLive {
                    Circle().fill(Color.red).frame(width: 5, height: 5)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                }
                Text(Self.timeRange(programme))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isLive ? Color.red.opacity(0.18) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isLive ? Color.red.opacity(0.5) : Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private static func timeRange(_ p: EPGProgramme) -> String {
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateFormat = "h:mm"
        return "\(fmt.string(from: p.start))–\(fmt.string(from: p.stop))"
    }
}
