import SwiftUI
import AetherCore

struct GlobalContentSearchView: View {
    let service: XstreamService?
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    @ObservedObject var homeViewModel: HomeViewModel

    @State private var query = ""
    @State private var vodResults: [XstreamVOD] = []
    @State private var seriesResults: [XstreamSeries] = []
    @State private var debounceTask: Task<Void, Never>?
    @State private var selectedVOD: XstreamVOD?
    @State private var selectedSeries: XstreamSeries?

    private var isLocalSearchAvailable: Bool {
        !homeViewModel.allVODs.isEmpty || !homeViewModel.allSeries.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Szukaj filmów i seriali...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
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
                    description: Text("Wpisz tytuł filmu lub serialu")
                )
            } else if !homeViewModel.isPhase1Loaded && service == nil {
                ContentUnavailableView(
                    "Ładowanie...",
                    systemImage: "arrow.circlepath",
                    description: Text("Wróć na stronę główną, żeby załadować bibliotekę")
                )
            } else if vodResults.isEmpty && seriesResults.isEmpty {
                ContentUnavailableView(
                    "Brak wyników",
                    systemImage: "rectangle.slash",
                    description: Text("Nie znaleziono '\(query)'")
                )
            } else {
                List {
                    if !vodResults.isEmpty {
                        Section("Filmy (\(vodResults.count))") {
                            ForEach(vodResults.prefix(50)) { vod in
                                SearchResultRow(
                                    posterURL: vod.streamIcon.flatMap(URL.init),
                                    title: vod.name,
                                    subtitle: cleanCategoryName(vod.categoryName),
                                    rating: vod.rating
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { selectedVOD = vod }
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
                                    rating: series.rating
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
        .onChange(of: query) { _, newVal in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await runSearch(query: newVal)
            }
        }
        .sheet(item: $selectedVOD) { vod in
            VODDetailSheet(vod: vod, credentials: credentials, player: player)
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

        let lower = query.lowercased()

        // Fast local search if cached data is available
        if isLocalSearchAvailable {
            vodResults = homeViewModel.allVODs.filter { $0.name.lowercased().contains(lower) }
            seriesResults = homeViewModel.allSeries.filter { $0.name.lowercased().contains(lower) }
            return
        }

        // Fallback: network search via service
        guard let svc = service else { return }
        vodResults = await svc.searchVODs(query: query)
        seriesResults = await svc.searchSeries(query: query)
    }

    private func cleanCategoryName(_ name: String?) -> String? {
        guard let n = name, !n.isEmpty else { return nil }
        let garbage = ["netflix", "apple", "amazon", "disney", "hbo", "premium", "4k"]
        let lower = n.lowercased()
        if garbage.contains(where: { lower.contains($0) }) { return nil }
        if n.unicodeScalars.contains(where: { $0.value >= 0x0600 && $0.value <= 0x06FF }) { return nil }
        return n
    }
}

// MARK: - SearchResultRow

struct SearchResultRow: View {
    let posterURL: URL?
    let title: String
    let subtitle: String?
    let rating: String?

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
