import SwiftUI
import AetherCore
import AetherUI

@MainActor
struct GlobalContentSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var vodStreams: [XstreamVOD] = []
    @State private var series: [XstreamSeries] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filterType: ContentType? = nil
    @State private var selectedSeries: XstreamSeries?

    // Debounce state
    @State private var debounceTask: Task<Void, Never>?
    @State private var debouncedQuery = ""

    private let xstreamService: XstreamService
    private let credentials: XstreamCredentials
    @Bindable var player: PlayerCore

    init(xstreamService: XstreamService, credentials: XstreamCredentials, player: PlayerCore) {
        self.xstreamService = xstreamService
        self.credentials = credentials
        self.player = player
    }

    private func loadContent() async {
        isLoading = true
        errorMessage = nil

        do {
            async let vodTask = xstreamService.vodStreams()
            async let seriesTask = xstreamService.seriesList()

            let (vod, seriesData) = try await (vodTask, seriesTask)
            vodStreams = vod
            series = seriesData
        } catch {
            errorMessage = "Failed to load content: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Debounced search

    private func onSearchTextChanged(_ text: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            debouncedQuery = text
        }
    }

    // MARK: - Filtered results by section

    private var filteredVOD: [XstreamVOD] {
        guard filterType == nil || filterType == .movie else { return [] }
        let q = debouncedQuery.lowercased()
        guard !q.isEmpty else { return [] }
        return vodStreams.filter { $0.name.lowercased().contains(q) }.prefix(50).map { $0 }
    }

    private var filteredSeries: [XstreamSeries] {
        guard filterType == nil || filterType == .series else { return [] }
        let q = debouncedQuery.lowercased()
        guard !q.isEmpty else { return [] }
        return series.filter { $0.name.lowercased().contains(q) }.prefix(50).map { $0 }
    }

    private var hasResults: Bool {
        !filteredVOD.isEmpty || !filteredSeries.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.aetherText.opacity(0.6))
                    .font(.system(size: 16))

                TextField("Szukaj filmów i seriali...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.aetherText)
                    .font(.system(size: 15))
                    .onChange(of: searchText) { _, new in onSearchTextChanged(new) }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        debouncedQuery = ""
                        debounceTask?.cancel()
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

            // Filter buttons
            HStack(spacing: 8) {
                FilterButton(title: "Wszystkie", isSelected: filterType == nil) {
                    filterType = nil
                }
                FilterButton(title: "Filmy", isSelected: filterType == .movie) {
                    filterType = .movie
                }
                FilterButton(title: "Seriale", isSelected: filterType == .series) {
                    filterType = .series
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.aetherBackground.opacity(0.8))

            Divider()

            // Results
            if isLoading {
                Spacer()
                ProgressView("Ładowanie zawartości…")
                    .controlSize(.large)
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.aetherDestructive)
                    Text(error)
                        .foregroundStyle(Color.aetherText)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else if debouncedQuery.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.aetherText.opacity(0.3))
                    Text("Wpisz aby przeszukać całą zawartość")
                        .foregroundStyle(Color.aetherText.opacity(0.6))
                }
                Spacer()
            } else if !hasResults {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.aetherText.opacity(0.3))
                    Text("Brak wyników dla \"\(debouncedQuery)\"")
                        .foregroundStyle(Color.aetherText.opacity(0.6))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        // VOD section
                        if !filteredVOD.isEmpty {
                            searchSection(title: "Filmy (\(filteredVOD.count))") {
                                ForEach(filteredVOD) { vod in
                                    SearchResultRow(
                                        title: vod.name,
                                        subtitle: vod.rating.flatMap(Double.init).map { String(format: "⭐ %.1f", $0) },
                                        coverURL: vod.streamIcon.flatMap(URL.init(string:)),
                                        typeLabel: "Film"
                                    ) {
                                        handleVOD(vod)
                                    }
                                }
                            }
                        }

                        // Series section
                        if !filteredSeries.isEmpty {
                            searchSection(title: "Seriale (\(filteredSeries.count))") {
                                ForEach(filteredSeries) { s in
                                    SearchResultRow(
                                        title: s.name,
                                        subtitle: s.releaseDate.map { String($0.prefix(4)) },
                                        coverURL: s.cover.flatMap(URL.init(string:)),
                                        typeLabel: "Serial"
                                    ) {
                                        handleSeries(s)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 500)
        .background(Color.aetherBackground)
        .task {
            await loadContent()
        }
        .sheet(item: $selectedSeries) { s in
            SeriesDetailView(series: s, credentials: credentials, player: player)
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

// MARK: - SearchResultRow (thumbnail 60x80 + info)

private struct SearchResultRow: View {
    let title: String
    let subtitle: String?
    let coverURL: URL?
    let typeLabel: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Thumbnail 60x80 (2:3)
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .empty:
                        Color.aetherSurface.overlay(
                            ProgressView().scaleEffect(0.6)
                        )
                    case .failure:
                        Color.aetherSurface.overlay(
                            Image(systemName: typeLabel == "Film" ? "film" : "tv")
                                .foregroundStyle(.secondary)
                        )
                    @unknown default:
                        Color.aetherSurface
                    }
                }
                .frame(width: 60, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Text(typeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(typeLabel == "Film" ? Color.blue.opacity(0.8) : Color.purple.opacity(0.8))
                        .clipShape(Capsule())
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
