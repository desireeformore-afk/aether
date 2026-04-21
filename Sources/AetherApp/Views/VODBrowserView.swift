import SwiftUI
import AetherCore

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

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.05, green: 0.05, blue: 0.05, opacity: 1).ignoresSafeArea()

            if homeViewModel.shelves.isEmpty && !homeViewModel.isFullyLoaded {
                vodLoadingSkeleton
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        WatchHistoryShelf(player: player)

                        if !heroBannerItems.isEmpty {
                            HeroBanner(items: heroBannerItems)
                                .padding(.bottom, -20)
                        }

                        // Streaming services section
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

                        // Genre section divider
                        if !homeViewModel.genreShelves.isEmpty {
                            sectionHeader("Gatunki")
                            ForEach(Array(homeViewModel.genreShelves.enumerated()), id: \.offset) { _, shelf in
                                CategoryShelf(
                                    title: shelf.title,
                                    items: shelfItemsWithTap(shelf.items)
                                )
                            }
                        }

                        // Remaining shelves (not matched to streaming/genre)
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
        }
        .onChange(of: homeViewModel.shelves.count) { _, _ in updateHeroBanner() }
        .onAppear {
            homeViewModel.load(credentials: credentials)
            updateHeroBanner()
        }
        .sheet(item: $selectedVOD) { vod in
            VODDetailSheet(vod: vod, credentials: credentials, player: player)
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

    // MARK: - Loading skeleton

    private var vodLoadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1))
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .shimmer()

            VStack(alignment: .leading, spacing: 32) {
                ForEach(0..<4, id: \.self) { _ in
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

            if isHovered {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()

                    if let rating = vod.rating, !rating.isEmpty, let ratingValue = Double(rating), ratingValue > 0 {
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

                    Text(vod.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
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

// MARK: - VODShimmerView

private struct VODShimmerView: View {
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

// MARK: - VODDetailSheet

struct VODDetailSheet: View {
    let vod: XstreamVOD
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.sRGB, red: 0.06, green: 0.06, blue: 0.08, opacity: 1).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Backdrop image with gradient overlay
                    ZStack(alignment: .bottomLeading) {
                        AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                ZStack {
                                    Color(.sRGB, red: 0.12, green: 0.12, blue: 0.14, opacity: 1)
                                    Image(systemName: "film")
                                        .font(.system(size: 64))
                                        .foregroundStyle(.white.opacity(0.15))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipped()

                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Color(.sRGB, red: 0.06, green: 0.06, blue: 0.08, opacity: 0.6), location: 0.5),
                                .init(color: Color(.sRGB, red: 0.06, green: 0.06, blue: 0.08, opacity: 1), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 280)
                    }

                    // Content below backdrop
                    VStack(alignment: .leading, spacing: 16) {

                        // Title
                        Text(vod.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(3)

                        // Metadata row: category + rating stars
                        HStack(spacing: 12) {
                            if let cat = vod.categoryName, !cat.isEmpty {
                                Text(cat)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let rating = vod.rating, !rating.isEmpty,
                               let ratingValue = Double(rating), ratingValue > 0 {
                                HStack(spacing: 3) {
                                    ForEach(0..<5) { i in
                                        Image(systemName: Double(i) < ratingValue / 2 ? "star.fill" : "star")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.yellow)
                                    }
                                    Text(String(format: "%.1f", ratingValue))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }

                        // Play button — large, blue, full width
                        Button {
                            playVOD()
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Odtwórz")
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        // Description placeholder (Xtream VOD list API doesn't include plot)
                        // Cast + genre info not available in list endpoint
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }

            // Dismiss button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.75))
                    .shadow(color: .black.opacity(0.5), radius: 4)
                    .padding(16)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 520, height: 620)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func playVOD() {
        let channel = vod.toChannel(credentials: credentials)
        Task { @MainActor in
            player.play(channel)
        }
    }
}
