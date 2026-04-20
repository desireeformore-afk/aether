import SwiftUI
import AetherCore

// MARK: - VODBrowserView

struct VODBrowserView: View {
    @ObservedObject var homeViewModel: HomeViewModel
    @Bindable var player: PlayerCore
    let credentials: XstreamCredentials

    @State private var selectedVOD: XstreamVOD?
    @State private var heroBannerItems: [HeroBannerItem] = []

    /// Convenience init for embedded usage (FloatingChannelPanel) without shared HomeViewModel.
    init(credentials: XstreamCredentials, player: PlayerCore, isEmbedded: Bool = false) {
        self.credentials = credentials
        self.player = player
        let vm = HomeViewModel()
        self._homeViewModel = ObservedObject(wrappedValue: vm)
    }

    /// Primary init — shared HomeViewModel (ContentView main layout).
    init(homeViewModel: HomeViewModel, player: PlayerCore, credentials: XstreamCredentials) {
        self._homeViewModel = ObservedObject(wrappedValue: homeViewModel)
        self.player = player
        self.credentials = credentials
    }

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.05, green: 0.05, blue: 0.05, opacity: 1).ignoresSafeArea()

            if homeViewModel.shelves.isEmpty && !homeViewModel.isFullyLoaded {
                vodLoadingSkeleton
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !heroBannerItems.isEmpty {
                            HeroBanner(items: heroBannerItems)
                        }

                        ForEach(Array(homeViewModel.shelves.enumerated()), id: \.offset) { _, shelf in
                            CategoryShelf(title: shelf.title, items: shelf.items)
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
    }

    private func updateHeroBanner() {
        guard let first = homeViewModel.shelves.first else { return }
        heroBannerItems = first.items.prefix(3).map { item in
            HeroBannerItem(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
        }
    }

    // MARK: - Loading skeleton

    private var vodLoadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1))
                .frame(maxWidth: .infinity)
                .frame(height: 380)
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
        HStack(alignment: .top, spacing: 20) {
            AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    ZStack {
                        Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15, opacity: 1)
                        Image(systemName: "film")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 140, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 12) {
                Text(vod.name)
                    .font(.system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if let rating = vod.rating, !rating.isEmpty, let ratingValue = Double(rating), ratingValue > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 14))
                        Text(String(format: "%.1f", ratingValue))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                Button {
                    playVOD()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Play Now")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)

                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 420, height: 270)
    }

    private func playVOD() {
        let channel = vod.toChannel(credentials: credentials)
        Task { @MainActor in
            player.play(channel)
        }
    }
}
