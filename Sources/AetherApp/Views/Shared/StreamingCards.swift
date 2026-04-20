import SwiftUI
import AetherCore

// MARK: - Data Models

struct HeroBannerItem {
    let title: String
    let imageURL: String?
    let onTap: () -> Void
}

struct ShelfItem: Identifiable {
    let id: String
    let title: String
    let imageURL: String?
    var vod: XstreamVOD?
    var series: XstreamSeries?
    let onTap: () -> Void
}

// MARK: - PosterCard

struct PosterCard: View {
    let title: String
    let imageURL: String?
    let onTap: () -> Void

    @State private var isHovered = false

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth * 3 / 2 }

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: imageURL.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .empty:
                    CardShimmerView()
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
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if isHovered {
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(title)
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
                            .init(color: .black.opacity(0.92), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.5 : 0), radius: 14, y: 8)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }
}

// MARK: - HeroBanner

struct HeroBanner: View {
    let items: [HeroBannerItem]
    @State private var currentIndex = 0

    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    private let bannerHeight: CGFloat = 420

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                bannerContent
            }
        }
    }

    @ViewBuilder
    private var bannerContent: some View {
        let item = items[min(currentIndex, items.count - 1)]
        ZStack(alignment: .bottomLeading) {
            // Cross-fade background image
            ZStack {
                ForEach(Array(items.enumerated()), id: \.offset) { index, bannerItem in
                    AsyncImage(url: bannerItem.imageURL.flatMap(URL.init(string:))) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color(.sRGB, red: 0.12, green: 0.12, blue: 0.12, opacity: 1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: bannerHeight)
                    .clipped()
                    .opacity(index == currentIndex ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8), value: currentIndex)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: bannerHeight)

            // Strong gradient — darker at bottom 40%
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.black.opacity(0.2), location: 0.45),
                    .init(color: Color.black.opacity(0.75), location: 0.72),
                    .init(color: Color.black, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: bannerHeight)

            // Content: title + play button + dots — bottom-left
            VStack(alignment: .leading, spacing: 14) {
                Text(item.title)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.4), value: currentIndex)

                Button(action: item.onTap) {
                    Label("▶ Odtwórz", systemImage: "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                if items.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<items.count, id: \.self) { i in
                            Circle()
                                .fill(i == currentIndex ? Color.white : Color.white.opacity(0.35))
                                .frame(
                                    width: i == currentIndex ? 9 : 5,
                                    height: i == currentIndex ? 9 : 5
                                )
                                .animation(.spring(duration: 0.3), value: currentIndex)
                        }
                    }
                }
            }
            .padding(.horizontal, 44)
            .padding(.bottom, 36)
        }
        .onReceive(timer) { _ in
            guard !items.isEmpty else { return }
            withAnimation {
                currentIndex = (currentIndex + 1) % items.count
            }
        }
    }
}

// MARK: - CategoryShelf

struct CategoryShelf: View {
    let title: String
    let items: [ShelfItem]
    var onMore: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                if let more = onMore {
                    Button(action: more) {
                        Text("Więcej →")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 24)
                }
            }
            .padding(.leading, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in
                        PosterCard(
                            title: item.title,
                            imageURL: item.imageURL,
                            onTap: item.onTap
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 20)
    }
}

// MARK: - CardShimmerView

struct CardShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1)
                LinearGradient(
                    colors: [.clear, .white.opacity(0.2), .clear],
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
