import SwiftUI
import AetherCore

struct SeriesBrowserView: View {
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    var isEmbedded: Bool = false

    @State private var categories: [XstreamSeriesCategory] = []
    @State private var seriesByCategory: [String: [XstreamSeries]] = [:]
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

    // MARK: - Embedded layout

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

    // MARK: - Category list (standalone)

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

    // MARK: - Grid content (Netflix-style sections)

    private var seriesGridContent: some View {
        Group {
            if isLoadingList {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedSeries.isEmpty && selectedCategory == nil && searchText.isEmpty {
                ContentUnavailableView(
                    "Pick a Category",
                    systemImage: "rectangle.stack.fill",
                    description: Text("Select a category on the left.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedSeries.isEmpty {
                ContentUnavailableView("No Series", systemImage: "tv")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                netflixGrid
            }
        }
        .background(Color.aetherBackground)
    }

    private var netflixGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !searchText.isEmpty {
                    sectionBlock(title: "Results", seriesList: displayedSeries)
                } else if selectedCategory != nil {
                    sectionBlock(title: selectedCategory?.name ?? "", seriesList: displayedSeries)
                } else {
                    ForEach(categories) { cat in
                        if let list = seriesByCategory[cat.id], !list.isEmpty {
                            sectionBlock(title: cat.name, seriesList: list)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func sectionBlock(title: String, seriesList: [XstreamSeries]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(.title3, design: .default, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(seriesList.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(Color.aetherPrimary)
                .frame(height: 2)
                .frame(maxWidth: 40)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                spacing: 16
            ) {
                ForEach(seriesList) { series in
                    SeriesCard(series: series)
                        .onTapGesture { selectedSeries = series }
                }
            }
        }
    }

    // MARK: - Filtered series

    private var displayedSeries: [XstreamSeries] {
        let base: [XstreamSeries]
        if let cat = selectedCategory {
            base = seriesByCategory[cat.id] ?? []
        } else if !seriesByCategory.isEmpty {
            base = categories.flatMap { seriesByCategory[$0.id] ?? [] }
        } else {
            base = []
        }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Data loading

    private func loadCategories() async {
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        categories = (try? await service.seriesCategories()) ?? []
    }

    private func loadList(for category: XstreamSeriesCategory) async {
        isLoadingList = true
        defer { isLoadingList = false }
        let fetched = (try? await service.seriesList(categoryID: category.id)) ?? []
        seriesByCategory[category.id] = fetched
    }
}

// MARK: - SeriesCard

private struct SeriesCard: View {
    let series: XstreamSeries
    @State private var isHovered = false

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth * 3 / 2 }  // 2:3 ratio

    var body: some View {
        ZStack(alignment: .bottom) {
            // Poster image
            AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .empty:
                    ShimmerView()
                case .failure:
                    ZStack {
                        Color.aetherSurface
                        Image(systemName: "tv")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color.aetherSurface
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Hover overlay
            if isHovered {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()

                    // Rating badge
                    if let rating = series.rating, let ratingValue = Double(rating), ratingValue > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text(String(format: "%.1f", ratingValue))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.65))
                        .clipShape(Capsule())
                    }

                    // Title + year
                    VStack(alignment: .leading, spacing: 2) {
                        Text(series.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if let year = series.releaseDate?.prefix(4) {
                            Text(String(year))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                .padding(10)
                .frame(width: cardWidth, height: cardHeight, alignment: .bottomLeading)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.5), location: 0.55),
                            .init(color: .black.opacity(0.9), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .transition(.opacity)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.4 : 0), radius: 12, y: 6)
        .animation(.easeInOut(duration: 0.18), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - ShimmerView

private struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.aetherSurface
                LinearGradient(
                    colors: [.clear, .white.opacity(0.25), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * geometry.size.width * 2 - geometry.size.width)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}
