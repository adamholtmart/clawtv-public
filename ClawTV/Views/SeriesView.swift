import SwiftUI

struct SeriesView: View {
    @EnvironmentObject var xtream: XtreamService
    @EnvironmentObject var store: PlaylistStore
    @State private var search: String = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Series")
                .task { await xtream.loadSeriesIfNeeded() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !xtream.isConfigured {
            unconfiguredState
        } else if xtream.isLoadingSeries && xtream.series.isEmpty {
            ProgressView("Loading series…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if xtream.series.isEmpty {
            emptyState
        } else {
            categoryGrid
        }
    }

    private var unconfiguredState: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Add Xtream credentials in Settings to browse series.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Settings → Xtream Codes Account")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.minus")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No series returned by your Xtream server.")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let err = xtream.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Button("Retry") { Task { await xtream.loadSeries() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var categoryGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TextField("Search series", text: $search)
                    .padding(.horizontal, 36)

                if !search.isEmpty {
                    seriesGrid(for: filteredSeries)
                        .padding(.horizontal, 36)
                } else {
                    ForEach(xtream.seriesCategories) { cat in
                        let inCat = xtream.series.filter { $0.categoryID == cat.id }
                        if !inCat.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(cat.name)
                                    .font(.title2.weight(.semibold))
                                    .padding(.leading, 36)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 18) {
                                        ForEach(Array(inCat.prefix(40))) { s in
                                            NavigationLink(value: s) {
                                                SeriesPoster(series: s)
                                            }
                                            .buttonStyle(.card)
                                        }
                                    }
                                    .padding(.horizontal, 36)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .navigationDestination(for: XtreamSeries.self) { SeriesDetailView(series: $0) }
    }

    private var filteredSeries: [XtreamSeries] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return xtream.series.filter { $0.name.lowercased().contains(q) }
    }

    private func seriesGrid(for items: [XtreamSeries]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(220), spacing: 18), count: 5),
            spacing: 28
        ) {
            ForEach(items) { s in
                NavigationLink(value: s) {
                    SeriesPoster(series: s)
                }
                .buttonStyle(.card)
            }
        }
    }
}

private struct SeriesPoster: View {
    let series: XtreamSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.white.opacity(0.05)
                if let urlStr = series.cover, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 220, height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(series.name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .frame(width: 220, alignment: .leading)
        }
    }
}

struct SeriesDetailView: View {
    let series: XtreamSeries
    @EnvironmentObject var xtream: XtreamService
    @EnvironmentObject var store: PlaylistStore
    @State private var info: XtreamSeriesInfo?
    @State private var selectedSeason: Int = 1
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if loading && info == nil {
                    ProgressView("Loading episodes…")
                        .padding(48)
                } else if let info, !info.seasons.isEmpty {
                    seasonPicker(info)
                    episodeList(info)
                } else {
                    Text("No episodes available.")
                        .foregroundStyle(.secondary)
                        .padding(48)
                }
            }
            .padding(.vertical, 32)
        }
        .task { await loadInfo() }
        .navigationTitle("")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 36) {
            SeriesPoster(series: series)
            VStack(alignment: .leading, spacing: 14) {
                Text(series.name)
                    .font(.largeTitle.weight(.bold))
                if let plot = series.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                if let cast = series.cast, !cast.isEmpty {
                    Text("Cast: \(cast)").font(.callout)
                }
                if let director = series.director, !director.isEmpty {
                    Text("Director: \(director)").font(.callout)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 48)
    }

    private func seasonPicker(_ info: XtreamSeriesInfo) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(info.seasons) { season in
                    Button {
                        selectedSeason = season.number
                    } label: {
                        Text("Season \(season.number)")
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedSeason == season.number ? .accentColor : .gray)
                }
            }
            .padding(.horizontal, 48)
        }
    }

    private func episodeList(_ info: XtreamSeriesInfo) -> some View {
        let season = info.seasons.first(where: { $0.number == selectedSeason })
            ?? info.seasons.first
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(season?.episodes ?? []) { ep in
                Button {
                    if let channel = xtream.channel(forEpisode: ep, seriesName: series.name) {
                        store.openChannel(channel)
                    }
                } label: {
                    HStack(spacing: 16) {
                        if let s = ep.still, let url = URL(string: s) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: Color.white.opacity(0.05)
                                }
                            }
                            .frame(width: 220, height: 124)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 220, height: 124)
                                .overlay(Image(systemName: "play.rectangle").foregroundStyle(.tertiary))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(ep.displayName)
                                .font(.headline)
                            if let plot = ep.plot, !plot.isEmpty {
                                Text(plot)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(.white.opacity(0.04), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.card)
            }
        }
        .padding(.horizontal, 48)
    }

    private func loadInfo() async {
        guard info == nil, !loading else { return }
        loading = true
        info = await xtream.loadSeriesInfo(seriesID: series.seriesID)
        loading = false
        if let first = info?.seasons.first {
            selectedSeason = first.number
        }
    }
}
