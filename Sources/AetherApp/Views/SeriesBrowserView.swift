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

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.05, green: 0.05, blue: 0.05, opacity: 1).ignoresSafeArea()

            if homeViewModel.seriesShelves.isEmpty && !homeViewModel.isFullyLoaded {
                seriesLoadingSkeleton
            } else {
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
            VODDetailSheet(vod: vod, credentials: credentials, player: player)
        }
    }

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

    // MARK: - Loading skeleton

    private var seriesLoadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1))
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .shimmer()

            VStack(alignment: .leading, spacing: 32) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.sRGB, red: 0.2, green: 0.2, blue: 0.2, opacity: 1))
                            .frame(width: 200, height: 22)
                            .shimmer()

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<8, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.sRGB, red: 0.18, green: 0.18, blue: 0.18, opacity: 1))
                                        .frame(width: 160, height: 240)
                                        .shimmer()
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
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

            if isHovered {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()

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
