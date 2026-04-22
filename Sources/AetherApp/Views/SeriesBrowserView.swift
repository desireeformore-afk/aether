import SwiftUI
import AetherCore

// MARK: - SeriesBrowserView

struct SeriesBrowserView: View {
    @ObservedObject var homeViewModel: HomeViewModel
    @Bindable var player: PlayerCore
    let credentials: XstreamCredentials

    @State private var heroBannerItems: [HeroBannerItem] = []
    @State private var selectedSeries: XstreamSeries?
    @State private var selectedVOD: XstreamVOD?
    @State private var selectedGenre: String? = nil

    // Unique category names from all series
    private var availableGenres: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for series in homeViewModel.allSeries {
            if let name = series.categoryName, !name.isEmpty, seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }

    // Items for the currently selected genre
    private var filteredSeriesItems: [ShelfItem] {
        guard let genre = selectedGenre else { return [] }
        return homeViewModel.allSeries
            .filter { $0.categoryName == genre }
            .map { series in
                ShelfItem(
                    id: String(series.id),
                    title: series.name,
                    imageURL: series.cover,
                    series: series,
                    onTap: { selectedSeries = series }
                )
            }
    }

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.05, green: 0.05, blue: 0.05, opacity: 1).ignoresSafeArea()

            if homeViewModel.seriesShelves.isEmpty && !homeViewModel.isFullyLoaded {
                seriesLoadingSkeleton
            } else {
                VStack(spacing: 0) {
                    genreFilterBar

                    if selectedGenre != nil {
                        filteredGridView
                    } else {
                        fullBrowseView
                    }
                }
            }
        }
        .onChange(of: homeViewModel.seriesShelves.count) { _, _ in updateHeroBanner() }
        .onAppear {
            homeViewModel.load(credentials: credentials)
            updateHeroBanner()
        }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series, credentials: credentials, player: player)
        }
        .sheet(item: $selectedVOD) { vod in
            VODDetailView(vod: vod, credentials: credentials, player: player)
        }
    }

    // MARK: - Genre filter bar

    private var genreFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                GenreFilterPill(title: "Wszystkie", isSelected: selectedGenre == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedGenre = nil }
                }
                ForEach(availableGenres, id: \.self) { genre in
                    GenreFilterPill(title: genre, isSelected: selectedGenre == genre) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedGenre = genre }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(Color(.sRGB, red: 0.05, green: 0.05, blue: 0.05, opacity: 1))
    }

    // MARK: - Filtered grid (single genre)

    private var filteredGridView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 14)],
                spacing: 14
            ) {
                ForEach(filteredSeriesItems) { item in
                    PosterCard(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Full browse view (all genres)

    private var fullBrowseView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                WatchHistoryShelf(player: player)

                if !heroBannerItems.isEmpty {
                    HeroBanner(items: heroBannerItems)
                        .padding(.bottom, -20)
                }

                ForEach(Array(homeViewModel.seriesShelves.enumerated()), id: \.offset) { _, shelf in
                    CategoryShelf(title: shelf.title, items: shelfItemsWithTap(shelf.items))
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Helpers

    private func shelfItemsWithTap(_ items: [ShelfItem]) -> [ShelfItem] {
        items.map { item in
            if let vod = item.vod {
                return ShelfItem(
                    id: item.id,
                    title: item.title,
                    imageURL: item.imageURL,
                    vod: vod,
                    onTap: { selectedVOD = vod }
                )
            }
            guard let series = item.series else { return item }
            return ShelfItem(
                id: item.id,
                title: item.title,
                imageURL: item.imageURL,
                series: series,
                onTap: { selectedSeries = series }
            )
        }
    }

    private func updateHeroBanner() {
        guard let first = homeViewModel.seriesShelves.first else { return }
        let tapped = shelfItemsWithTap(first.items)
        heroBannerItems = tapped.prefix(3).map { item in
            HeroBannerItem(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
        }
    }

    // MARK: - Loading skeleton (3x3 shimmer grid)

    private var seriesLoadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Filter bar skeleton
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.sRGB, red: 0.2, green: 0.2, blue: 0.2, opacity: 1))
                        .frame(width: 80, height: 30)
                        .shimmer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 14)],
                spacing: 14
            ) {
                ForEach(0..<9, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1))
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .shimmer()
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - SeriesCard

struct SeriesCard: View {
    let series: XstreamSeries
    @State private var isHovered = false

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth * 3 / 2 }

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .empty:
                    SeriesShimmerView()
                case .failure:
                    ZStack {
                        Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1)
                        Image(systemName: "tv")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Rating badge top-right
            if let rating = series.rating, let ratingValue = Double(rating), ratingValue > 0 {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                            Text(String(format: "%.1f", ratingValue))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(6)
                    }
                    Spacer()
                }
                .frame(width: cardWidth, height: cardHeight)
            }

            // Title overlay at bottom
            VStack(alignment: .leading, spacing: 3) {
                Spacer()
                Text(series.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let year = series.releaseDate?.prefix(4) {
                    Text(String(year))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(8)
            .frame(width: cardWidth, height: cardHeight, alignment: .bottomLeading)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.45), location: 0.5),
                        .init(color: .black.opacity(0.88), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(width: cardWidth, height: cardHeight)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.4 : 0), radius: 12, y: 6)
        .animation(.easeInOut(duration: 0.18), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - SeriesShimmerView

private struct SeriesShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1)
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
