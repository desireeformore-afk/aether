import SwiftUI
import AetherCore
import AetherUI

@MainActor
struct GlobalContentSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var vodStreams: [XstreamVOD] = []
    @State private var series: [XstreamSeries] = []
    @State private var filteredVods: [XstreamVOD] = []
    @State private var filteredSeries: [XstreamSeries] = []
    @State private var displayLimitVod = 20
    @State private var displayLimitSeries = 20
    @State private var isLoading = false
    @State private var isLoaded = false
    @State private var errorMessage: String?
    @State private var filterType: ContentType? = nil
    @State private var selectedSeries: XstreamSeries?
    @State private var debounceTask: Task<Void, Never>?

    private let xstreamService: XstreamService
    private let credentials: XstreamCredentials
    @Bindable var player: PlayerCore

    init(xstreamService: XstreamService, credentials: XstreamCredentials, player: PlayerCore) {
        self.xstreamService = xstreamService
        self.credentials = credentials
        self.player = player
    }

    // MARK: - Category name cleaning

    private func cleanCategoryName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let lower = raw.lowercased()
        if lower.contains("arabic") || lower.contains("arab") || raw.contains("بث") || raw.contains("عربي") {
            return "Inne"
        }
        var cleaned = raw
        for token in ["4K", "FHD", "HD", "Premium", "Ultra", "UHD"] {
            cleaned = cleaned.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        if cleaned.isEmpty { return "Inne" }
        return String(cleaned.prefix(20))
    }

    // MARK: - Loading

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        let cachedV = await xstreamService.cachedVods
        let cachedS = await xstreamService.cachedSeries
        if !cachedV.isEmpty || !cachedS.isEmpty {
            vodStreams = cachedV
            series = cachedS
            isLoaded = true
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            async let vodTask = xstreamService.vodStreams()
            async let seriesTask = xstreamService.seriesList()
            let (vod, seriesData) = try await (vodTask, seriesTask)
            vodStreams = vod
            series = seriesData
            isLoaded = true
        } catch {
            errorMessage = "Failed to load content: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Filtering with debounce

    private func scheduleFilter() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            applyFilter()
        }
    }

    private func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            filteredVods = []
            filteredSeries = []
            displayLimitVod = 20
            displayLimitSeries = 20
            return
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if filterType == nil || filterType == .movie {
            filteredVods = vodStreams.filter { $0.name.range(of: q, options: options) != nil }
        } else {
            filteredVods = []
        }
        if filterType == nil || filterType == .series {
            filteredSeries = series.filter { $0.name.range(of: q, options: options) != nil }
        } else {
            filteredSeries = []
        }
        displayLimitVod = 20
        displayLimitSeries = 20
    }

    // MARK: - Popular (empty state grid)

    private var popularVods: [XstreamVOD] {
        vodStreams
            .sorted { (Double($0.rating ?? "") ?? 0) > (Double($1.rating ?? "") ?? 0) }
            .prefix(20)
            .map { $0 }
    }

    // MARK: - Paged slices

    private var pagedVods: [XstreamVOD] {
        Array(filteredVods.prefix(displayLimitVod))
    }

    private var pagedSeries: [XstreamSeries] {
        Array(filteredSeries.prefix(displayLimitSeries))
    }

    private var isSearching: Bool {
        searchText.trimmingCharacters(in: .whitespaces).count >= 2
    }

    private var hasResults: Bool {
        !filteredVods.isEmpty || !filteredSeries.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterBar
            Divider()

            if isLoading {
                Spacer()
                ProgressView("Ładowanie zawartości…").controlSize(.large)
                Spacer()
            } else if let error = errorMessage {
                errorView(error)
            } else if !isSearching {
                discoverView
            } else if !hasResults {
                noResultsView
            } else {
                resultsView
            }
        }
        .frame(minWidth: 520, minHeight: 520)
        .background(Color.aetherBackground)
        .task { await loadIfNeeded() }
        .onChange(of: searchText) { _, _ in scheduleFilter() }
        .onChange(of: filterType) { _, _ in applyFilter() }
        .sheet(item: $selectedSeries) { s in
            SeriesDetailView(series: s, credentials: credentials, player: player)
        }
    }

    // MARK: - Sub-views

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.aetherText.opacity(0.6))
                .font(.system(size: 16))

            TextField("Szukaj filmów i seriali…", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.aetherText)
                .font(.system(size: 15))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    debounceTask?.cancel()
                    filteredVods = []
                    filteredSeries = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.aetherText.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.aetherSurface)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterButton(title: "Wszystkie", isSelected: filterType == nil) { filterType = nil }
            FilterButton(title: "Filmy", isSelected: filterType == .movie) { filterType = .movie }
            FilterButton(title: "Seriale", isSelected: filterType == .series) { filterType = .series }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.aetherBackground.opacity(0.8))
    }

    private var resultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !filteredVods.isEmpty {
                    searchSection(title: "Filmy (\(filteredVods.count))") {
                        ForEach(pagedVods) { vod in
                            SearchResultRow(
                                title: vod.name,
                                categoryLabel: cleanCategoryName(vod.categoryName),
                                subtitle: vod.rating.flatMap(Double.init).map { String(format: "%.1f", $0) },
                                coverURL: vod.streamIcon.flatMap(URL.init(string:)),
                                typeLabel: "Film"
                            ) { handleVOD(vod) }
                        }
                        if pagedVods.count < filteredVods.count {
                            Color.clear
                                .frame(height: 1)
                                .onAppear { displayLimitVod += 20 }
                        }
                    }
                }

                if !filteredSeries.isEmpty {
                    searchSection(title: "Seriale (\(filteredSeries.count))") {
                        ForEach(pagedSeries) { s in
                            SearchResultRow(
                                title: s.name,
                                categoryLabel: cleanCategoryName(s.categoryName),
                                subtitle: s.releaseDate.map { String($0.prefix(4)) },
                                coverURL: s.cover.flatMap(URL.init(string:)),
                                typeLabel: "Serial"
                            ) { handleSeries(s) }
                        }
                        if pagedSeries.count < filteredSeries.count {
                            Color.clear
                                .frame(height: 1)
                                .onAppear { displayLimitSeries += 20 }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var discoverView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !vodStreams.isEmpty {
                    Text("Odkryj coś nowego")
                        .font(.system(.headline, design: .default, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    Rectangle()
                        .fill(Color.aetherPrimary)
                        .frame(height: 2)
                        .frame(maxWidth: 36)
                        .padding(.horizontal, 16)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(popularVods) { vod in
                            VStack(spacing: 6) {
                                AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    default:
                                        Color.aetherSurface.overlay(
                                            Image(systemName: "film")
                                                .foregroundStyle(.secondary)
                                        )
                                    }
                                }
                                .frame(width: 100, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(vod.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture { handleVOD(vod) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else if !isLoading {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.aetherText.opacity(0.3))
                        Text("Wpisz tytuł aby wyszukać")
                            .foregroundStyle(Color.aetherText.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
            }
        }
    }

    private var noResultsView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.aetherText.opacity(0.3))
                Text("Brak wyników dla \"\(searchText.trimmingCharacters(in: .whitespaces))\"")
                    .foregroundStyle(Color.aetherText.opacity(0.6))
            }
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.aetherDestructive)
                Text(message)
                    .foregroundStyle(Color.aetherText)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func searchSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .default, weight: .bold))
                .foregroundStyle(.primary)

            Rectangle()
                .fill(Color.aetherPrimary)
                .frame(height: 2)
                .frame(maxWidth: 36)

            content()
        }
    }

    // MARK: - Actions

    private func handleVOD(_ vod: XstreamVOD) {
        let channel = vod.toChannel(credentials: credentials)
        player.play(channel)
        dismiss()
    }

    private func handleSeries(_ s: XstreamSeries) {
        selectedSeries = s
    }
}

// MARK: - SearchResultRow

private struct SearchResultRow: View {
    let title: String
    let categoryLabel: String
    let subtitle: String?
    let coverURL: URL?
    let typeLabel: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .empty:
                        Color.aetherSurface.overlay(ProgressView().scaleEffect(0.6))
                    case .failure:
                        Color.aetherSurface.overlay(
                            Image(systemName: typeLabel == "Film" ? "film" : "tv")
                                .foregroundStyle(.secondary)
                        )
                    @unknown default:
                        Color.aetherSurface
                    }
                }
                .frame(width: 50, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !categoryLabel.isEmpty {
                        Text(categoryLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        if let subtitle, !subtitle.isEmpty {
                            if typeLabel == "Film", let rating = Double(subtitle) {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption2)
                                    Text(String(format: "%.1f", rating))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(typeLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(typeLabel == "Film" ? Color.blue.opacity(0.8) : Color.purple.opacity(0.8))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isHovered ? Color.aetherPrimary : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.aetherPrimary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - FilterButton

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.aetherCaption)
                .foregroundStyle(isSelected ? Color.aetherBackground : Color.aetherText)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isSelected ? Color.aetherPrimary : Color.aetherSecondary.opacity(0.3))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ContentType

enum ContentType {
    case movie
    case series
}

// MARK: - Preview

#Preview {
    let credentials = XstreamCredentials(
        baseURL: URL(string: "http://example.com")!,
        username: "test",
        password: "test"
    )
    GlobalContentSearchView(
        xstreamService: XstreamService(credentials: credentials),
        credentials: credentials,
        player: PlayerCore()
    )
}
