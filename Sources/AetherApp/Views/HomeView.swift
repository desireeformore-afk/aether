import SwiftUI
import AetherCore

// MARK: - HomeView

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Bindable var player: PlayerCore
    let credentials: XstreamCredentials

    @State private var heroBannerIndex = 0
    @State private var selectedVOD: XstreamVOD?

    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.heroBannerVODs.isEmpty {
                loadingSkeleton
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !viewModel.heroBannerVODs.isEmpty {
                            heroBanner
                        }
                        VStack(alignment: .leading, spacing: 32) {
                            if !viewModel.popularVODs.isEmpty {
                                ShelfRow(
                                    title: "Popularne teraz",
                                    items: viewModel.popularVODs,
                                    player: player,
                                    credentials: credentials
                                )
                            }
                            if !viewModel.topSeries.isEmpty {
                                SeriesShelfRow(
                                    title: "Seriale",
                                    items: viewModel.topSeries,
                                    player: player,
                                    credentials: credentials
                                )
                            }
                            if !viewModel.recentVODs.isEmpty {
                                ShelfRow(
                                    title: "Ostatnio dodane",
                                    items: viewModel.recentVODs,
                                    player: player,
                                    credentials: credentials
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 32)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            guard !viewModel.heroBannerVODs.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.8)) {
                heroBannerIndex = (heroBannerIndex + 1) % viewModel.heroBannerVODs.count
            }
        }
        .sheet(item: $selectedVOD) { vod in
            VODDetailSheet(vod: vod, credentials: credentials, player: player)
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        let vod = viewModel.heroBannerVODs[min(heroBannerIndex, viewModel.heroBannerVODs.count - 1)]
        return ZStack(alignment: .bottomLeading) {
            AsyncImage(url: vod.streamIcon.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color(.sRGB, red: 0.12, green: 0.12, blue: 0.12, opacity: 1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 420)
            .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.5), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 420)

            VStack(alignment: .leading, spacing: 12) {
                Text(vod.name)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .lineLimit(2)

                if let rating = vod.rating, !rating.isEmpty, rating != "0" {
                    Label(rating, systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 14, weight: .medium))
                }

                HStack(spacing: 12) {
                    Button(action: { player.play(vod.toChannel(credentials: credentials)) }) {
                        Label("Odtwórz", systemImage: "play.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: { selectedVOD = vod }) {
                        Label("Info", systemImage: "info.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    ForEach(0..<viewModel.heroBannerVODs.count, id: \.self) { i in
                        Circle()
                            .fill(i == heroBannerIndex ? Color.white : Color.white.opacity(0.4))
                            .frame(
                                width: i == heroBannerIndex ? 10 : 6,
                                height: i == heroBannerIndex ? 10 : 6
                            )
                            .animation(.spring(duration: 0.3), value: heroBannerIndex)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 36)
        }
        .animation(.easeInOut(duration: 0.6), value: heroBannerIndex)
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
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
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.sRGB, red: 0.18, green: 0.18, blue: 0.18, opacity: 1))
                                        .frame(width: 130, height: 195)
                                        .shimmer()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - ShelfRow (VOD)

struct ShelfRow: View {
    let title: String
    let items: [XstreamVOD]
    @Bindable var player: PlayerCore
    let credentials: XstreamCredentials

    @State private var selectedVOD: XstreamVOD?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { vod in
                        VODCard(vod: vod)
                            .onTapGesture { selectedVOD = vod }
                    }
                }
            }
        }
        .sheet(item: $selectedVOD) { vod in
            VODDetailSheet(vod: vod, credentials: credentials, player: player)
        }
    }
}

// MARK: - SeriesShelfRow

struct SeriesShelfRow: View {
    let title: String
    let items: [XstreamSeries]
    @Bindable var player: PlayerCore
    let credentials: XstreamCredentials

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { series in
                        SeriesCard(series: series)
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

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: vod.streamIcon.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderCard
                case .empty:
                    Color(.sRGB, red: 0.18, green: 0.18, blue: 0.18, opacity: 1)
                @unknown default:
                    Color(.sRGB, red: 0.18, green: 0.18, blue: 0.18, opacity: 1)
                }
            }
            .frame(width: 130, height: 195)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if isHovered {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .center, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(vod.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                .padding(10)
                .frame(width: 130, height: 195, alignment: .bottomLeading)
            }
        }
        .frame(width: 130, height: 195)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.5 : 0.2), radius: isHovered ? 12 : 4)
        .animation(.spring(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderCard: some View {
        ZStack {
            Color(.sRGB, red: 0.18, green: 0.18, blue: 0.18, opacity: 1)
            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.3))
                Text(vod.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
            .padding(8)
        }
    }
}

// MARK: - SeriesCard

struct SeriesCard: View {
    let series: XstreamSeries
    @State private var isHovered = false

    var body: some View {
        AsyncImage(url: series.cover.flatMap(URL.init)) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fill)
            default:
                Color(.sRGB, red: 0.18, green: 0.18, blue: 0.18, opacity: 1)
            }
        }
        .frame(width: 130, height: 195)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.5 : 0.2), radius: isHovered ? 12 : 4)
        .animation(.spring(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Shimmer modifier

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { _ in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.12), .clear],
                    startPoint: .init(x: phase, y: 0),
                    endPoint: .init(x: phase + 0.5, y: 0)
                )
            }
        )
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
    }
}

// MARK: - WelcomeView

struct WelcomeView: View {
    @State private var showAddPlaylist = false
    @State private var gradientOffset: CGFloat = 0
    @Environment(\.modelContext) private var modelContext

    var onPlaylistAdded: (PlaylistRecord) -> Void

    var body: some View {
        ZStack {
            animatedBackground

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "tv.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.4), radius: 20)

                    Text("Aether")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Twój prywatny odtwarzacz IPTV")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }

                VStack(spacing: 12) {
                    Button {
                        showAddPlaylist = true
                    } label: {
                        Label("Dodaj playlistę Xtream", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 260)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Text("Obsługuje M3U i Xtream Codes")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.sRGB, red: 0.051, green: 0.051, blue: 0.051, opacity: 1))
        .sheet(isPresented: $showAddPlaylist) {
            AddPlaylistSheet { playlist in
                onPlaylistAdded(playlist)
            }
        }
        .onAppear { startGradientAnimation() }
    }

    private var animatedBackground: some View {
        ZStack {
            RadialGradient(
                colors: [Color.blue.opacity(0.15), .clear],
                center: UnitPoint(x: 0.3 + gradientOffset * 0.2, y: 0.4),
                startRadius: 0,
                endRadius: 400
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.12), .clear],
                center: UnitPoint(x: 0.7 - gradientOffset * 0.15, y: 0.6),
                startRadius: 0,
                endRadius: 350
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: gradientOffset)
    }

    private func startGradientAnimation() {
        gradientOffset = 1
    }
}
