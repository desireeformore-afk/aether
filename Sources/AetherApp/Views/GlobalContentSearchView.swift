import SwiftUI
import AetherCore
import AetherUI

struct GlobalContentSearchView: View {
    private static let resultLimit = 30

    let service: XstreamService?
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    @ObservedObject var homeViewModel: HomeViewModel
    var initialQuery: String? = nil

    @State private var query = ""
    @State private var vodResults: [UnifiedMediaItem] = []
    @State private var seriesResults: [UnifiedMediaItem] = []
    @State private var isSearching = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedVODItem: ShelfItem?
    @State private var selectedSeries: XstreamSeries?
    @FocusState private var isSearchFocused: Bool

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
            .background(AetherTheme.ColorToken.elevated)
            .clipShape(RoundedRectangle(cornerRadius: AetherTheme.Radius.control))
            .padding()

            if query.isEmpty {
                ContentUnavailableView(
                    "Szukaj",
                    systemImage: "magnifyingglass",
                    description: Text("Type a movie or series title")
                )
            } else if isSearching && vodResults.isEmpty && seriesResults.isEmpty {
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
                            ForEach(Array(vodResults.prefix(Self.resultLimit)), id: \.id) { vod in
                                SearchResultRow(
                                    posterURL: vod.posterURLString.flatMap(URL.init),
                                    title: vod.title,
                                    subtitle: vod.categoryName,
                                    rating: vod.rating,
                                    year: vod.year,
                                    variantCount: vod.variants.count
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedVODItem = shelfItem(from: vod)
                                }
                            }
                        }
                    }

                    if !seriesResults.isEmpty {
                        Section("Seriale (\(seriesResults.count))") {
                            ForEach(Array(seriesResults.prefix(Self.resultLimit)), id: \.id) { series in
                                SearchResultRow(
                                    posterURL: series.posterURLString.flatMap(URL.init),
                                    title: series.title,
                                    subtitle: series.genre,
                                    rating: series.rating,
                                    year: series.year,
                                    variantCount: nil
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { selectedSeries = series.series }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AetherTheme.ColorToken.background)
        .onAppear {
            if let q = initialQuery, !q.isEmpty { query = q }
            primeSearchIndex()
        }
        .onDisappear {
            debounceTask?.cancel()
            searchTask?.cancel()
        }
        .onChange(of: initialQuery) { _, newVal in
            if let q = newVal, !q.isEmpty { query = q }
        }
        .onChange(of: query) { _, newVal in
            debounceTask?.cancel()
            searchTask?.cancel()
            if newVal.isEmpty {
                isSearching = false
                vodResults = []
                seriesResults = []
                return
            }
            isSearching = true
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                searchTask = Task { @MainActor in
                    await runSearch(query: newVal)
                }
            }
        }
        .onChange(of: homeViewModel.allVODs.count) { _, _ in
            refreshSearchIndexFromHome()
        }
        .onChange(of: homeViewModel.allSeries.count) { _, _ in
            refreshSearchIndexFromHome()
        }
        .onChange(of: homeViewModel.catalogSnapshot.vodItems.count) { _, _ in
            refreshSearchIndexFromHome()
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

    private func primeSearchIndex() {
        refreshSearchIndexFromHome()
    }

    private func refreshSearchIndexFromHome() {
        let currentQuery = query
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            guard !Task.isCancelled, !currentQuery.isEmpty else { return }
            await runSearch(query: currentQuery)
        }
    }

    private func runSearch(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            vodResults = []
            seriesResults = []
            isSearching = false
            return
        }

        let immediate = await homeViewModel.searchCatalog(query: trimmedQuery, limit: Self.resultLimit)
        guard !Task.isCancelled, self.query == query else { return }
        vodResults = immediate.movies
        seriesResults = immediate.series
        isSearching = false
    }

    private func shelfItem(from item: UnifiedMediaItem) -> ShelfItem? {
        guard let vod = item.primaryVOD else { return nil }
        return ShelfItem(
            id: item.id,
            title: item.title,
            imageURL: item.posterURLString,
            vod: vod,
            tags: item.tags,
            alternateVODs: item.vodVariants,
            onTap: {}
        )
    }
}

// MARK: - SearchResultRow

struct SearchResultRow: View {
    let posterURL: URL?
    let title: String
    let subtitle: String?
    let rating: String?
    let year: String?
    let variantCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            CachedImageView(url: posterURL) {
                Color(.sRGB, red: 0.2, green: 0.2, blue: 0.2, opacity: 1)
            } content: { image in
                image.resizable().aspectRatio(contentMode: .fill)
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

                HStack(spacing: 8) {
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

                    if let variantCount, variantCount > 1 {
                        Text("\(variantCount) variants")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
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
