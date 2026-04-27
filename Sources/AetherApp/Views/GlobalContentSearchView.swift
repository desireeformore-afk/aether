import SwiftUI
import AetherCore

struct GlobalContentSearchView: View {
    let service: XstreamService?
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    @ObservedObject var homeViewModel: HomeViewModel
    var initialQuery: String? = nil

    @State private var query = ""
    @State private var vodResults: [XstreamVOD] = []
    @State private var seriesResults: [XstreamSeries] = []
    @State private var isSearching = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var selectedVODItem: ShelfItem?
    @State private var selectedSeries: XstreamSeries?
    @FocusState private var isSearchFocused: Bool

    private var isLocalSearchAvailable: Bool {
        !homeViewModel.allVODs.isEmpty || !homeViewModel.allSeries.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search movies and series...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isSearchFocused)
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding()

            if query.isEmpty {
                ContentUnavailableView(
                    "Szukaj",
                    systemImage: "magnifyingglass",
                    description: Text("Type a movie or series title")
                )
            } else if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                        .frame(width: 38, height: 38)
                    Text("Szukam…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !homeViewModel.isPhase1Loaded && service == nil {
                ContentUnavailableView(
                    "Loading...",
                    systemImage: "arrow.circlepath",
                    description: Text("Go to Home to load the library")
                )
            } else if vodResults.isEmpty && seriesResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No results for \"\(query)\"")
                        .font(.title3.bold())
                    Button("Clear") { query = "" }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !vodResults.isEmpty {
                        Section("Filmy (\(vodResults.count))") {
                            ForEach(vodResults.prefix(50)) { vod in
                                SearchResultRow(
                                    posterURL: vod.streamIcon.flatMap(URL.init),
                                    title: vod.name,
                                    subtitle: cleanCategoryName(vod.categoryName),
                                    rating: vod.rating,
                                    year: nil
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let item = ShelfItem(id: "\(vod.id)", title: vod.name, imageURL: vod.streamIcon, vod: vod, onTap: {})
                                    selectedVODItem = item
                                }
                            }
                        }
                    }

                    if !seriesResults.isEmpty {
                        Section("Seriale (\(seriesResults.count))") {
                            ForEach(seriesResults.prefix(50)) { series in
                                SearchResultRow(
                                    posterURL: series.cover.flatMap(URL.init),
                                    title: series.name,
                                    subtitle: series.genre,
                                    rating: series.rating,
                                    year: series.releaseDate
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { selectedSeries = series }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.black)
        .onAppear {
            if let q = initialQuery, !q.isEmpty { query = q }
        }
        .onChange(of: initialQuery) { _, newVal in
            if let q = newVal, !q.isEmpty { query = q }
        }
        .onChange(of: query) { _, newVal in
            debounceTask?.cancel()
            if newVal.isEmpty {
                isSearching = false
                vodResults = []
                seriesResults = []
                return
            }
            isSearching = true
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await runSearch(query: newVal)
                isSearching = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("AetherOpenSearch"))) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                isSearchFocused = true
            }
        }
        .sheet(item: $selectedVODItem) { vod in
            VODDetailView(item: vod, credentials: credentials, player: player)
        }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series, credentials: credentials, player: player)
        }
    }

    private func runSearch(query: String) async {
        guard !query.isEmpty else {
            vodResults = []
            seriesResults = []
            return
        }

        // Fast local search if cached data is available
        if isLocalSearchAvailable {
            vodResults = homeViewModel.allVODs
                .filter { vodScore(query, $0) > 0 }
                .sorted { vodScore(query, $0) > vodScore(query, $1) }
            seriesResults = homeViewModel.allSeries
                .filter { seriesScore(query, $0) > 0 }
                .sorted { seriesScore(query, $0) > seriesScore(query, $1) }
            return
        }

        // Fallback: network search via service
        guard let svc = service else { return }
        vodResults = await svc.searchVODs(query: query)
        seriesResults = await svc.searchSeries(query: query)
    }

    private func strippedTitle(_ name: String) -> String {
        var s = name
        for _ in 0..<3 {
            if let range = s.range(of: #"^[A-Z0-9\+\-\.]{1,10}[\s]*[\-\|][\s]+"#,
                                   options: [.regularExpression, .caseInsensitive]) {
                s.removeSubrange(range)
            } else { break }
        }
        return s
    }

    // MARK: - Scoring

    private func fuzzyScore(_ query: String, in text: String) -> Int {
        let q = query.lowercased()
        let t = text.lowercased()
        let ts = strippedTitle(t)

        if ts == q { return 200 }
        if t == q { return 190 }
        if ts.hasPrefix(q) || t.hasPrefix(q) { return 150 }
        let words = ts.split(separator: " ")
        if words.contains(where: { $0.hasPrefix(q) }) { return 120 }
        if t.contains(q) { return 100 }
        if ts.contains(q) { return 90 }

        // Fuzzy subsequence match on stripped title
        var qi = q.startIndex
        for ch in ts {
            if qi < q.endIndex && ch == q[qi] {
                qi = q.index(after: qi)
            }
        }
        if qi == q.endIndex {
            let score = Int(Double(q.count) / Double(max(ts.count, 1)) * 80)
            return max(1, min(80, score))
        }
        return 0
    }

    private func vodScore(_ query: String, _ vod: XstreamVOD) -> Int {
        let nameScore = fuzzyScore(query, in: vod.name)
        let catScore = vod.categoryName.map { fuzzyScore(query, in: $0) / 2 } ?? 0
        return max(nameScore, catScore)
    }

    private func seriesScore(_ query: String, _ series: XstreamSeries) -> Int {
        let nameScore = fuzzyScore(query, in: series.name)
        let genreScore = series.genre.map { fuzzyScore(query, in: $0) / 2 } ?? 0
        return max(nameScore, genreScore)
    }

    private func cleanCategoryName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let category = CategoryNormalizer.normalize(
            rawName: name,
            provider: .xtream,
            contentType: .movie
        )
        return category.isPrimaryVisible ? category.displayName : nil
    }
}

// MARK: - SearchResultRow

struct SearchResultRow: View {
    let posterURL: URL?
    let title: String
    let subtitle: String?
    let rating: String?
    let year: String?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Color(.sRGB, red: 0.2, green: 0.2, blue: 0.2, opacity: 1)
                }
            }
            .frame(width: 54, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let r = rating, !r.isEmpty, r != "0" {
                    Label(r, systemImage: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                }

                if let y = year, !y.isEmpty {
                    Text(y)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - FilterButton (kept for compatibility)

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.white.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
