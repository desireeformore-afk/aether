import SwiftUI
import AetherCore

// MARK: - HomeView

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Bindable var player: PlayerCore
    let credentials: XstreamCredentials

    @State private var selectedVOD: XstreamVOD?
    @State private var selectedSeries: XstreamSeries?
    @State private var heroBannerItems: [HeroBannerItem] = []

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.05, green: 0.05, blue: 0.05, opacity: 1).ignoresSafeArea()

            if !viewModel.isPhase1Loaded {
                loadingSkeleton
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        WatchHistoryShelf(player: player)

                        if !heroBannerItems.isEmpty {
                            HeroBanner(items: heroBannerItems)
                                .padding(.bottom, -20)
                        }

                        ForEach(Array(viewModel.shelves.enumerated()), id: \.offset) { _, shelf in
                            CategoryShelf(
                                title: shelf.title,
                                items: shelfItemsWithTap(shelf.items, credentials: credentials)
                            )
                        }

                        if !viewModel.seriesShelves.isEmpty {
                            ForEach(Array(viewModel.seriesShelves.enumerated()), id: \.offset) { _, shelf in
                                CategoryShelf(
                                    title: shelf.title,
                                    items: shelfItemsWithTap(shelf.items, credentials: credentials)
                                )
                            }
                        }

                        if !viewModel.liveItems.isEmpty {
                            CategoryShelf(title: "Na żywo", items: shelfItemsWithTap(viewModel.liveItems, credentials: credentials))
                        }

                        Spacer(minLength: 40)
                    }
                }
            }

            if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            viewModel.load(credentials: credentials)
            updateHeroBanner()
        }
        .onChange(of: viewModel.shelves.count) { _, _ in updateHeroBanner() }
        .sheet(item: $selectedVOD) { vod in
            VODDetailSheet(vod: vod, credentials: credentials, player: player)
        }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series, credentials: credentials, player: player)
        }
    }

    private func updateHeroBanner() {
        guard let first = viewModel.shelves.first else { return }
        let tapped = shelfItemsWithTap(first.items, credentials: credentials)
        heroBannerItems = tapped.prefix(5).map { item in
            HeroBannerItem(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
        }
    }

    private func shelfItemsWithTap(_ items: [ShelfItem], credentials: XstreamCredentials) -> [ShelfItem] {
        items.map { item in
            if let vod = item.vod {
                return ShelfItem(
                    id: item.id,
                    title: item.title,
                    imageURL: item.imageURL,
                    vod: vod,
                    series: nil,
                    onTap: { player.play(vod.toChannel(credentials: credentials)) }
                )
            } else if let series = item.series {
                return ShelfItem(
                    id: item.id,
                    title: item.title,
                    imageURL: item.imageURL,
                    vod: nil,
                    series: series,
                    onTap: { selectedSeries = series }
                )
            } else if let liveStream = item.stream {
                return ShelfItem(
                    id: item.id,
                    title: item.title,
                    imageURL: item.imageURL,
                    stream: liveStream,
                    onTap: { player.play(liveStream.toChannel(credentials: credentials)) }
                )
            }
            return item
        }
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
                            HStack(spacing: 14) {
                                ForEach(0..<8, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.sRGB, red: 0.18, green: 0.18, blue: 0.18, opacity: 1))
                                        .frame(width: 160, height: 240)
                                        .shimmer()
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
            }
            .padding(.horizontal, 0)
        }
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
                        Label("Add Playlist", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 260)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("n", modifiers: .command)

                    HStack(spacing: 16) {
                        Label("M3U URL", systemImage: "link")
                        Label("Xtream Codes", systemImage: "server.rack")
                        Label("Local file", systemImage: "doc")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
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
