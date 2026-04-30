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
    var subtitle: String? = nil
    var rating: String? = nil
    var year: String? = nil
    var variantCount: Int = 0
    
    let onTap: () -> Void
}

// MARK: - PosterCard

struct PosterCard: View {
    let title: String
    let imageURL: String?
    var tags: Set<VODTag> = []
    var subtitle: String? = nil
    var rating: String? = nil
    var year: String? = nil
    var variantCount: Int = 0
    let onTap: () -> Void

    @State private var isHovered = false

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth * 3 / 2 }
    private var ratingValue: Double {
        guard let rating else { return 0 }
        return Double(rating.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var metadataLine: String? {
        [year, subtitle]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " • ")
            .nilIfEmpty
    }

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

                VStack {
                    HStack(alignment: .top, spacing: 6) {
                        if ratingValue > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text(String(format: "%.1f", ratingValue))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(AetherTheme.ColorToken.gold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.68), in: Capsule())
                        }

                        Spacer(minLength: 0)

                        if variantCount > 1 {
                            Text("\(variantCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.68), in: Capsule())
                                .accessibilityLabel("\(variantCount) variants")
                        }
                    }
                    Spacer()
                }
                .padding(7)
                .frame(width: cardWidth, height: cardHeight)

                VStack(alignment: .leading, spacing: 5) {
                    Spacer()

                    if isHovered, !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(tags).sorted(by: { $0.rawValue < $1.rawValue }).prefix(3)) { tag in
                                Text(tag.rawValue)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(tag.isResolution ? .black : .white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(tag.isResolution ? AetherTheme.ColorToken.gold : Color.white.opacity(0.24))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }

                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if isHovered, let metadataLine {
                        Text(metadataLine)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .frame(width: cardWidth, height: cardHeight, alignment: .bottomLeading)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: isHovered ? 0.18 : 0.50),
                            .init(color: .black.opacity(isHovered ? 0.48 : 0.20), location: 0.62),
                            .init(color: .black.opacity(isHovered ? 0.92 : 0.72), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: AetherTheme.Radius.card))
                .animation(AetherTheme.Motion.quick, value: isHovered)

                if isHovered {
                    RoundedRectangle(cornerRadius: AetherTheme.Radius.card)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        .transition(.opacity)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .scaleEffect(isHovered ? 1.045 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.50 : 0.16), radius: isHovered ? 18 : 8, y: isHovered ? 12 : 4)
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
                            subtitle: item.subtitle,
                            rating: item.rating,
                            year: item.year,
                            variantCount: item.variantCount,
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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
