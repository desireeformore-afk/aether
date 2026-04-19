import SwiftUI
import AetherCore

struct SeriesBrowserView: View {
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    var isEmbedded: Bool = false

    @State private var categories: [XstreamSeriesCategory] = []
    @State private var seriesList: [XstreamSeries] = []
    @State private var selectedCategory: XstreamSeriesCategory?
    @State private var isLoadingCategories = false
    @State private var isLoadingList = false
    @State private var searchText = ""
    @State private var selectedSeries: XstreamSeries?

    private let service: XstreamService

    init(credentials: XstreamCredentials, player: PlayerCore, isEmbedded: Bool = false) {
        self.credentials = credentials
        self.player = player
        self.isEmbedded = isEmbedded
        self.service = XstreamService(credentials: credentials)
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if isEmbedded {
            embeddedLayout
        } else {
            NavigationSplitView {
                categoryList
            } detail: {
                seriesGrid
            }
            .navigationTitle("Series")
            .frame(minWidth: 720, minHeight: 500)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .task { await loadCategories() }
            .sheet(item: $selectedSeries) { series in
                SeriesDetailView(series: series, credentials: credentials, player: player)
            }
        }
    }

    // Inline layout for panel embedding (no NavigationSplitView)
    private var embeddedLayout: some View {
        HStack(spacing: 0) {
            // Category rail
            VStack(spacing: 0) {
                Text("Categories")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                Divider()

                if isLoadingCategories {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedCategory) {
                        ForEach(categories) { cat in
                            Text(cat.name)
                                .font(.system(size: 12))
                                .lineLimit(2)
                                .tag(cat)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(width: 140)
            .background(Color.aetherSurface)
            .onChange(of: selectedCategory) { _, cat in
                guard let cat else { return }
                Task { await loadList(for: cat) }
            }

            Divider()

            // Content area
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search series…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.aetherSurface)

                Divider()

                seriesGridContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadCategories() }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series, credentials: credentials, player: player)
        }
    }

    private var categoryList: some View {
        List(selection: $selectedCategory) {
            if isLoadingCategories {
                ProgressView("Loading categories…")
            } else {
                ForEach(categories) { cat in
                    Text(cat.name)
                        .font(.aetherBody)
                        .tag(cat)
                }
            }
        }
        .navigationTitle("Categories")
        .onChange(of: selectedCategory) { _, cat in
            guard let cat else { return }
            Task { await loadList(for: cat) }
        }
    }

    private var seriesGrid: some View {
        seriesGridContent
            .searchable(text: $searchText, prompt: "Search series")
            .background(Color.aetherBackground)
    }

    private var seriesGridContent: some View {
        Group {
            if isLoadingList {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedCategory == nil {
                ContentUnavailableView(
                    "Pick a Category",
                    systemImage: "rectangle.stack.fill",
                    description: Text("Select a category on the left.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredList.isEmpty {
                ContentUnavailableView("No Series", systemImage: "tv")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                        ForEach(filteredList) { series in
                            SeriesCard(series: series)
                                .onTapGesture { selectedSeries = series }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.aetherBackground)
    }

    private var filteredList: [XstreamSeries] {
        guard !searchText.isEmpty else { return seriesList }
        return seriesList.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func loadCategories() async {
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        categories = (try? await service.seriesCategories()) ?? []
    }

    private func loadList(for category: XstreamSeriesCategory) async {
        seriesList = []
        isLoadingList = true
        defer { isLoadingList = false }
        seriesList = (try? await service.seriesList(categoryID: category.id)) ?? []
    }
}

// MARK: - SeriesCard

private struct SeriesCard: View {
    let series: XstreamSeries
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure, .empty:
                        ZStack {
                            Color.aetherSurface
                            Image(systemName: "tv")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    @unknown default:
                        ShimmerView()
                    }
                }
                .frame(width: 110, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if isHovered {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 110, height: 165)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .onHover { isHovered = $0 }

            VStack(alignment: .leading, spacing: 4) {
                Text(series.name)
                    .font(.aetherCaption)
                    .foregroundStyle(Color.aetherText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let year = series.releaseDate?.prefix(4) {
                        Text(String(year))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let rating = series.rating, let ratingValue = Double(rating), ratingValue > 0 {
                        HStack(spacing: 2) {
                            Text("⭐")
                                .font(.system(size: 10))
                            Text(String(format: "%.1f", ratingValue))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 110, alignment: .leading)
        }
    }
}

// MARK: - ShimmerView

private struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        LinearGradient(
            colors: [
                Color.aetherSurface,
                Color.aetherSurface.opacity(0.7),
                Color.aetherSurface
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: phase)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 300
            }
        }
    }
}
