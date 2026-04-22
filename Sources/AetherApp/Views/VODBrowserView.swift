import SwiftUI
import SwiftData
import AetherCore

// MARK: - VODSortOrder

enum VODSortOrder: String, CaseIterable {
    case `default` = "Domyślne"
    case titleAZ = "Tytuł A-Z"
    case titleZA = "Tytuł Z-A"
    case ratingHigh = "Ocena ↓"
    case ratingLow = "Ocena ↑"
}

// MARK: - VODBrowserView

struct VODBrowserView: View {
    @ObservedObject var homeViewModel: HomeViewModel
    @Bindable var player: PlayerCore
    let credentials: XstreamCredentials

    @State private var selectedVOD: XstreamVOD?
    @State private var selectedSeries: XstreamSeries?
    @State private var heroBannerItems: [HeroBannerItem] = []
    @State private var selectedServiceTitle: String = ""
    @State private var selectedServiceItems: [ShelfItem] = []
    @State private var showServiceDetail = false
    @State private var selectedGenre: String? = nil
    @State private var sortOrder: VODSortOrder = .default

    @Query(sort: \WatchHistoryRecord.watchedAt, order: .reverse)
    private var watchHistory: [WatchHistoryRecord]

    // MARK: - Computed

    private var availableGenres: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let garbage = ["netflix", "apple", "amazon", "disney", "hbo", "prime", "peacock", "paramount", "4k", "premium", "iptv"]
        for vod in homeViewModel.allVODs {
            guard let name = vod.categoryName, !name.isEmpty, name.count <= 40 else { continue }
            let lower = name.lowercased()
            guard !garbage.contains(where: { lower.contains($0) }) else { continue }
            let asciiCount = name.unicodeScalars.filter { $0.value < 0x0250 }.count
            guard asciiCount > name.count / 2 else { continue }
            if seen.insert(name).inserted { result.append(name) }
        }
        return result.sorted()
    }

    private var filteredVODItems: [ShelfItem] {
        guard let genre = selectedGenre else { return [] }
        var items = homeViewModel.allVODs
            .filter { $0.categoryName == genre }
            .map { vod in
                ShelfItem(
                    id: String(vod.id),
                    title: vod.name,
                    imageURL: vod.streamIcon,
                    vod: vod,
                    onTap: { selectedVOD = vod }
                )
            }

        switch sortOrder {
        case .default: break
        case .titleAZ: items.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .titleZA: items.sort { $0.title.localizedCompare($1.title) == .orderedDescending }
        case .ratingHigh:
            items.sort { (Double($0.vod?.rating ?? "") ?? 0) > (Double($1.vod?.rating ?? "") ?? 0) }
        case .ratingLow:
            items.sort { (Double($0.vod?.rating ?? "") ?? 0) < (Double($1.vod?.rating ?? "") ?? 0) }
        }
        return items
    }

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.05, green: 0.05, blue: 0.05, opacity: 1).ignoresSafeArea()

            if homeViewModel.shelves.isEmpty && !homeViewModel.isFullyLoaded {
                vodLoadingSkeleton
            } else {
                VStack(spacing: 0) {
                    genreFilterBar

                    if selectedGenre != nil {
                        Text("\(filteredVODItems.count) tytułów")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        filteredGridView
                    } else {
                        fullBrowseView
                    }
                }
            }
        }
        .onChange(of: homeViewModel.shelves.count) { _, _ in updateHeroBanner() }
        .onAppear {
            homeViewModel.load(credentials: credentials)
            updateHeroBanner()
        }
        .sheet(item: $selectedVOD) { vod in
            VODDetailView(vod: vod, credentials: credentials, player: player)
        }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series, credentials: credentials, player: player)
        }
        .sheet(isPresented: $showServiceDetail) {
            StreamingServiceDetailView(
                title: selectedServiceTitle,
                items: selectedServiceItems,
                player: player,
                credentials: credentials
            )
        }
    }

    // MARK: - Genre filter bar

    private var genreFilterBar: some View {
        HStack(spacing: 0) {
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

            Picker("Sortuj", selection: $sortOrder) {
                ForEach(VODSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .foregroundStyle(.secondary)
            .padding(.trailing, 12)
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
                ForEach(filteredVODItems) { item in
                    VODGridCell(item: item, watchHistory: watchHistory)
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

                if !homeViewModel.streamingServiceShelves.isEmpty {
                    sectionHeader("Serwisy streamingowe")
                    ForEach(Array(homeViewModel.streamingServiceShelves.enumerated()), id: \.offset) { _, shelf in
                        CategoryShelf(
                            title: shelf.title,
                            items: shelfItemsWithTap(shelf.items),
                            onMore: {
                                selectedServiceTitle = shelf.title
                                selectedServiceItems = shelfItemsWithTap(homeViewModel.allItemsForService(shelf.title))
                                showServiceDetail = true
                            }
                        )
                    }
                }

                if !homeViewModel.genreShelves.isEmpty {
                    sectionHeader("Gatunki")
                    ForEach(Array(homeViewModel.genreShelves.enumerated()), id: \.offset) { _, shelf in
                        CategoryShelf(
                            title: shelf.title,
                            items: shelfItemsWithTap(shelf.items)
                        )
                    }
                }

                let usedTitles = Set(homeViewModel.streamingServiceShelves.map(\.title) +
                                    homeViewModel.genreShelves.map(\.title))
                ForEach(Array(homeViewModel.shelves.enumerated()), id: \.offset) { _, shelf in
                    if !usedTitles.contains(shelf.title) {
                        CategoryShelf(
                            title: shelf.title,
                            items: shelfItemsWithTap(shelf.items)
                        )
                    }
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.8)
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 4)
    }

    private func shelfItemsWithTap(_ items: [ShelfItem]) -> [ShelfItem] {
        items.map { item in
            if let vod = item.vod {
                return ShelfItem(
                    id: item.id, title: item.title, imageURL: item.imageURL,
                    vod: vod, series: nil,
                    onTap: { selectedVOD = vod }
                )
            } else if let series = item.series {
                return ShelfItem(
                    id: item.id, title: item.title, imageURL: item.imageURL,
                    vod: nil, series: series,
                    onTap: { selectedSeries = series }
                )
            } else if let stream = item.stream {
                return ShelfItem(
                    id: item.id, title: item.title, imageURL: item.imageURL,
                    stream: stream,
                    onTap: { player.play(stream.toChannel(credentials: credentials)) }
                )
            }
            return item
        }
    }

    private func updateHeroBanner() {
        guard let first = homeViewModel.shelves.first else { return }
        let tapped = shelfItemsWithTap(first.items)
        heroBannerItems = tapped.prefix(3).map { item in
            HeroBannerItem(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
        }
    }

    // MARK: - Loading skeleton (3x3 shimmer grid)

    private var vodLoadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 20) {
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

// MARK: - VODGridCell

private struct VODGridCell: View {
    let item: ShelfItem
    let watchHistory: [WatchHistoryRecord]

    private var progressRecord: WatchHistoryRecord? {
        guard let vodID = item.vod?.id else { return nil }
        return watchHistory.first { $0.streamURLString.contains(String(vodID)) }
    }

    var body: some View {
        let record = progressRecord
        if let record, record.progressFraction > 0.02, record.progressFraction < 0.97 {
            ZStack(alignment: .bottom) {
                PosterCard(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * record.progressFraction, height: 3)
                }
                .frame(height: 3)
                .padding(.horizontal, 4)
            }
        } else {
            PosterCard(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
        }
    }
}

// MARK: - VODCard

struct VODCard: View {
    let vod: XstreamVOD
    @State private var isHovered = false

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth * 3 / 2 }

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .empty:
                    VODShimmerView()
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    ZStack {
                        Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1)
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if let rating = vod.rating, !rating.isEmpty, let ratingValue = Double(rating), ratingValue > 0 {
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

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(vod.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
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

// MARK: - VODShimmerView

private struct VODShimmerView: View {
    @State private var phase: CGFloat = -0.5

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1)
            LinearGradient(
                colors: [.clear, .white.opacity(0.25), .clear],
                startPoint: UnitPoint(x: phase, y: 0),
                endPoint: UnitPoint(x: phase + 0.5, y: 0)
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

// MARK: - GenreFilterPill

struct GenreFilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}
