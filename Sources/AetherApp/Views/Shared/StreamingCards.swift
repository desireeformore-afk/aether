import SwiftUI
import AetherCore
import AetherUI

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
    var stream: XstreamStream?
    
    // The Clean Engine properties
    var tags: Set<VODTag> = []
    var alternateVODs: [XstreamVOD] = []
    
    let onTap: () -> Void
}

// MARK: - PosterCard

struct PosterCard: View {
    let title: String
    let imageURL: String?
    var tags: Set<VODTag> = []
    let onTap: () -> Void

    @State private var isHovered = false

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth * 3 / 2 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                CachedImageView(url: imageURL.flatMap(URL.init(string:))) {
                    CardShimmerView()
                } content: { image in
                    image.resizable().aspectRatio(2/3, contentMode: .fill)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: AetherTheme.Radius.card))

                if isHovered {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        
                        if !tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(Array(tags).sorted(by: { $0.rawValue < $1.rawValue })) { tag in
                                    Text(tag.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(tag.isResolution ? .black : .white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(tag.isResolution ? AetherTheme.ColorToken.gold : Color.white.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                        
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
                    .clipShape(RoundedRectangle(cornerRadius: AetherTheme.Radius.card))
                    .transition(.opacity)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.6 : 0.15), radius: isHovered ? 20 : 8, y: isHovered ? 12 : 4)
            .animation(AetherTheme.Motion.spring, value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - HeroBanner

struct HeroBanner: View {
    let items: [HeroBannerItem]
    @State private var currentIndex = 0
    @State private var appeared = false

    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    private let bannerHeight: CGFloat = 420

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                bannerContent
                    .opacity(appeared ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.5)) {
                            appeared = true
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var bannerContent: some View {
        let item = items[min(currentIndex, items.count - 1)]
        ZStack(alignment: .bottomLeading) {
            // Cross-fade background images
            ZStack {
                ForEach(Array(items.enumerated()), id: \.offset) { index, bannerItem in
                    CachedImageView(url: bannerItem.imageURL.flatMap(URL.init(string:))) {
                        Color(.sRGB, red: 0.12, green: 0.12, blue: 0.12, opacity: 1)
                    } content: { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: bannerHeight)
                    .scaleEffect(index == currentIndex ? 1.08 : 1.0)
                    .animation(.linear(duration: 7), value: currentIndex)
                    .clipped()
                    .opacity(index == currentIndex ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8), value: currentIndex)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: bannerHeight)

            // Left vignette for text contrast
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.6), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 340)
                Spacer()
            }
            .frame(height: bannerHeight)

            // Bottom gradient — subtle fade for text readability only
            LinearGradient(
                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.7)]),
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: bannerHeight)

            // Content: title + play button + progress dots
            VStack(alignment: .leading, spacing: 14) {
                Text(item.title)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .lineLimit(2)
                    .id("hero-title-\(currentIndex)")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .opacity
                    ))

                Button(action: item.onTap) {
                    Label("Odtwórz", systemImage: "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(AetherTheme.ColorToken.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AetherTheme.Radius.control))
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverScaleButtonStyle())
                .id("hero-button-\(currentIndex)")

                if items.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<items.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentIndex ? Color.white : Color.white.opacity(0.35))
                                .frame(
                                    width: i == currentIndex ? 20 : 6,
                                    height: 5
                                )
                                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentIndex)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .padding(.horizontal, 44)
            .padding(.bottom, 36)
        }
        .onReceive(timer) { _ in
            guard !items.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
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
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    Text(title)
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(.white)
                }

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
            .padding(.leading, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in
                        PosterCard(
                            title: item.title,
                            imageURL: item.imageURL,
                            tags: item.tags,
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
    @State private var phase: CGFloat = -0.5

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1)
            LinearGradient(
                colors: [.clear, .white.opacity(0.2), .clear],
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
