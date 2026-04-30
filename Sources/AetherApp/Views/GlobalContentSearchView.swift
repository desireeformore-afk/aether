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
            searchBar

            if query.isEmpty {
                searchEmptyState(
                    title: "Search",
                    icon: "magnifyingglass",
                    subtitle: "Movies and series are matched locally from the loaded catalog."
                )
            } else if isSearching && vodResults.isEmpty && seriesResults.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .frame(width: 38, height: 38)
                    Text("Searching…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !homeViewModel.isPhase1Loaded && service == nil {
                searchEmptyState(
                    title: "Catalog Loading",
                    icon: "arrow.circlepath",
                    subtitle: "Open Home once so Aether can build the local search index."
                )
            } else if vodResults.isEmpty && seriesResults.isEmpty {
                searchEmptyState(
                    title: "No Results",
                    icon: "rectangle.slash",
                    subtitle: "Nothing matched \"\(query)\"."
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if !vodResults.isEmpty {
                            searchSection(title: "Movies", count: vodResults.count) {
                                LazyVGrid(columns: searchColumns, spacing: 12) {
                                    ForEach(Array(vodResults.prefix(Self.resultLimit)), id: \.id) { vod in
                                        SearchResultCard(
                                            posterURL: vod.posterURLString.flatMap(URL.init),
                                            title: vod.title,
                                            subtitle: vod.categoryName ?? vod.genre,
                                            rating: vod.rating,
                                            year: vod.year,
                                            variantCount: vod.variants.count,
                                            systemImage: "film.fill"
                                        ) {
                                            selectedVODItem = shelfItem(from: vod)
                                        }
                                    }
                                }
                            }
                        }

                        if !seriesResults.isEmpty {
                            searchSection(title: "Series", count: seriesResults.count) {
                                LazyVGrid(columns: searchColumns, spacing: 12) {
                                    ForEach(Array(seriesResults.prefix(Self.resultLimit)), id: \.id) { series in
                                        SearchResultCard(
                                            posterURL: series.posterURLString.flatMap(URL.init),
                                            title: series.title,
                                            subtitle: series.categoryName ?? series.genre,
                                            rating: series.rating,
                                            year: series.year,
                                            variantCount: nil,
                                            systemImage: "tv.fill"
                                        ) {
                                            selectedSeries = series.series
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
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
            subtitle: item.categoryName ?? item.genre,
            rating: item.rating,
            year: item.year,
            variantCount: item.variants.count,
            onTap: {}
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AetherTheme.ColorToken.secondaryText)
            TextField("Search movies and series", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AetherTheme.ColorToken.primaryText)
                .focused($isSearchFocused)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AetherTheme.ColorToken.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(AetherTheme.ColorToken.elevated, in: RoundedRectangle(cornerRadius: AetherTheme.Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: AetherTheme.Radius.control)
                .stroke(isSearchFocused ? AetherTheme.ColorToken.accent.opacity(0.55) : AetherTheme.ColorToken.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var searchColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 12)]
    }

    @ViewBuilder
    private func searchSection<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AetherTheme.ColorToken.primaryText)
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AetherTheme.ColorToken.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AetherTheme.ColorToken.surface, in: Capsule())
                Spacer()
            }
            content()
        }
    }

    private func searchEmptyState(title: String, icon: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AetherTheme.ColorToken.tertiaryText)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AetherTheme.ColorToken.primaryText)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AetherTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SearchResultCard

struct SearchResultCard: View {
    let posterURL: URL?
    let title: String
    let subtitle: String?
    let rating: String?
    let year: String?
    let variantCount: Int?
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CachedImageView(url: posterURL) {
                    ZStack {
                        AetherTheme.ColorToken.surface
                        Image(systemName: systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(AetherTheme.ColorToken.tertiaryText)
                    }
                } content: { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                }
                .frame(width: 58, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AetherTheme.ColorToken.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let sub = subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AetherTheme.ColorToken.secondaryText)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let r = rating, !r.isEmpty, r != "0" {
                            Label(r, systemImage: "star.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AetherTheme.ColorToken.gold)
                        }

                        if let y = year, !y.isEmpty {
                            Text(y)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AetherTheme.ColorToken.tertiaryText)
                        }

                        if let variantCount, variantCount > 1 {
                            Text("\(variantCount) variants")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AetherTheme.ColorToken.secondaryText)
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isHovered ? AetherTheme.ColorToken.primaryText : AetherTheme.ColorToken.tertiaryText)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
            .background(isHovered ? AetherTheme.ColorToken.elevated : AetherTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: AetherTheme.Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: AetherTheme.Radius.control)
                    .stroke(isHovered ? Color.white.opacity(0.18) : AetherTheme.ColorToken.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(AetherTheme.Motion.quick, value: isHovered)
        .onHover { isHovered = $0 }
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
