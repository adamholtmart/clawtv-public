import SwiftUI

struct MoviesView: View {
    @EnvironmentObject var xtream: XtreamService
    @EnvironmentObject var store: PlaylistStore
    @State private var selectedCategory: XtreamCategory?
    @State private var search: String = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Movies")
                .task { await xtream.loadMoviesIfNeeded() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !xtream.isConfigured {
            unconfiguredState
        } else if xtream.isLoadingMovies && xtream.movies.isEmpty {
            ProgressView("Loading movies…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if xtream.movies.isEmpty {
            emptyState
        } else {
            categoryGrid
        }
    }

    private var unconfiguredState: some View {
        VStack(spacing: 18) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Add Xtream credentials in Settings to browse movies.")
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
            Image(systemName: "film")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No movies returned by your Xtream server.")
                .font(.title3)
                .foregroundStyle(.secondary)
            if let err = xtream.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Button("Retry") { Task { await xtream.loadMovies() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var categoryGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TextField("Search movies", text: $search)
                    .textContentType(.none)
                    .padding(.horizontal, 36)

                if !search.isEmpty {
                    movieGrid(for: filteredMovies)
                        .padding(.horizontal, 36)
                } else {
                    ForEach(xtream.movieCategories) { cat in
                        let inCat = xtream.movies.filter { $0.categoryID == cat.id }
                        if !inCat.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(cat.name)
                                    .font(.title2.weight(.semibold))
                                    .padding(.leading, 36)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 18) {
                                        ForEach(Array(inCat.prefix(40))) { movie in
                                            NavigationLink(value: movie) {
                                                MoviePoster(movie: movie)
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
        .navigationDestination(for: XtreamMovie.self) { MovieDetailView(movie: $0) }
    }

    private var filteredMovies: [XtreamMovie] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return xtream.movies.filter { $0.name.lowercased().contains(q) }
    }

    private func movieGrid(for items: [XtreamMovie]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(220), spacing: 18), count: 5),
            spacing: 28
        ) {
            ForEach(items) { movie in
                NavigationLink(value: movie) {
                    MoviePoster(movie: movie)
                }
                .buttonStyle(.card)
            }
        }
    }
}

private struct MoviePoster: View {
    let movie: XtreamMovie

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.white.opacity(0.05)
                if let urlStr = movie.icon, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: "film")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 220, height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(movie.name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .frame(width: 220, alignment: .leading)
        }
    }
}

struct MovieDetailView: View {
    let movie: XtreamMovie
    @EnvironmentObject var xtream: XtreamService
    @EnvironmentObject var store: PlaylistStore

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 36) {
                MoviePoster(movie: movie)
                VStack(alignment: .leading, spacing: 18) {
                    Text(movie.name)
                        .font(.largeTitle.weight(.bold))
                    HStack(spacing: 18) {
                        if let release = movie.releaseDate, !release.isEmpty {
                            metaPill("calendar", release)
                        }
                        if let rating = movie.rating, !rating.isEmpty {
                            metaPill("star.fill", rating)
                        }
                    }
                    if let plot = movie.plot, !plot.isEmpty {
                        Text(plot)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    if let cast = movie.cast, !cast.isEmpty {
                        labeled("Cast", cast)
                    }
                    if let director = movie.director, !director.isEmpty {
                        labeled("Director", director)
                    }
                    Button {
                        if let channel = xtream.channel(forMovie: movie) {
                            store.openChannel(channel)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 12)
                }
                Spacer()
            }
            .padding(48)
        }
        .navigationTitle("")
    }

    private func metaPill(_ system: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
            Text(text)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value).font(.callout)
        }
    }
}
