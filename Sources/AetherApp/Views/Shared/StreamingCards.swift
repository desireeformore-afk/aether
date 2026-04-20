import SwiftUI

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
                            .init(color: .black.opacity(0.9), location: 1)
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
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.4 : 0), radius: 12, y: 6)
        .animation(.easeInOut(duration: 0.18), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }
}

// MARK: - HeroBanner

struct HeroBanner: View {
    let items: [HeroBannerItem]
    @State private var currentIndex = 0

    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

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
            AsyncImage(url: item.imageURL.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color(.sRGB, red: 0.12, green: 0.12, blue: 0.12, opacity: 1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 380)
            .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.4), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 380)

            VStack(alignment: .leading, spacing: 12) {
                Text(item.title)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Button(action: item.onTap) {
                        Label("Odtwórz", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentIndex ? Color.white : Color.white.opacity(0.4))
                            .frame(
                                width: i == currentIndex ? 10 : 6,
                                height: i == currentIndex ? 10 : 6
                            )
                            .animation(.spring(duration: 0.3), value: currentIndex)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .animation(.easeInOut(duration: 0.6), value: currentIndex)
        .onReceive(timer) { _ in
            guard !items.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                currentIndex = (currentIndex + 1) % items.count
            }
        }
    }
}

// MARK: - CategoryShelf

struct CategoryShelf: View {
    let title: String
    let items: [ShelfItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.leading, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        PosterCard(
                            title: item.title,
                            imageURL: item.imageURL,
                            onTap: item.onTap
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 24)
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
