import SwiftUI
import SwiftData
import AetherCore

// MARK: - HomeView

/// Netflix/Apple TV–style home screen shown when a playlist is active.
/// Shows a rotating hero banner + horizontal shelves of VOD, series, and live TV.
struct HomeView: View {
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore

    @State private var heroBannerVODs: [XstreamVOD] = []
    @State private var popularVODs: [XstreamVOD] = []
    @State private var recentVODs: [XstreamVOD] = []
    @State private var series: [XstreamSeries] = []
    @State private var heroBannerIndex: Int = 0
    @State private var heroRotationTask: Task<Void, Never>?
    @State private var isLoading = true
    @State private var selectedVOD: XstreamVOD?

    private let service: XstreamService

    init(credentials: XstreamCredentials, player: PlayerCore) {
        self.credentials = credentials
        self.player = player
        self.service = XstreamService(credentials: credentials)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    loadingPlaceholder
                } else {
                    if !heroBannerVODs.isEmpty {
                        heroBanner
                    }
                    shelves
                        .padding(.top, 24)
                }
            }
        }
        .background(Color(hex: "#1A1A1A").ignoresSafeArea())
        .task { await loadContent() }
        .onDisappear { heroRotationTask?.cancel() }
        .sheet(item: $selectedVOD) { vod in
            VODDetailSheet(vod: vod, credentials: credentials, player: player)
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        let vod = heroBannerVODs[heroBannerIndex]
        return ZStack(alignment: .bottomLeading) {
            // Poster background
            AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 2)
                default:
                    Color(hex: "#2A2A2A")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipped()

            // Gradient overlay
            LinearGradient(
                colors: [.clear, Color(hex: "#1A1A1A").opacity(0.7), Color(hex: "#1A1A1A")],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)

            // Content
            VStack(alignment: .leading, spacing: 10) {
                Text(vod.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Button {
                        let channel = vod.toChannel(credentials: credentials)
                        player.play(channel)
                    } label: {
                        Label("Odtwórz", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedVOD = vod
                    } label: {
                        Label("Info", systemImage: "info.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                // Page indicator
                if heroBannerVODs.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(heroBannerVODs.indices, id: \.self) { i in
                            Circle()
                                .fill(i == heroBannerIndex ? Color.white : Color.white.opacity(0.35))
                                .frame(width: i == heroBannerIndex ? 8 : 6,
                                       height: i == heroBannerIndex ? 8 : 6)
                                .animation(.easeInOut(duration: 0.25), value: heroBannerIndex)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipped()
    }

    // MARK: - Shelves

    private var shelves: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !popularVODs.isEmpty {
                shelf(title: "🔥 Popularne", items: popularVODs)
            }
            if !recentVODs.isEmpty {
                shelf(title: "🎬 Ostatnio dodane", items: recentVODs)
            }
            if !series.isEmpty {
                seriesShelf
            }
        }
        .padding(.bottom, 32)
    }

    private func shelf(title: String, items: [XstreamVOD]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { vod in
                        VODCard(vod: vod, credentials: credentials, player: player)
                            .onTapGesture { selectedVOD = vod }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var seriesShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("📺 Seriale")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(series) { item in
                        SeriesCard(series: item)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.4)
                .tint(.white)
            Text("Ładowanie…")
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 400)
    }

    // MARK: - Data loading

    private func loadContent() async {
        isLoading = true
        async let vodStreams = (try? service.vodStreams()) ?? []
        async let seriesList = (try? service.seriesList()) ?? []

        let (allVODs, allSeries) = await (vodStreams, seriesList)

        // Sort by rating for "Popular" shelf
        let sorted = allVODs.sorted {
            (Double($0.rating ?? "") ?? 0) > (Double($1.rating ?? "") ?? 0)
        }

        heroBannerVODs = Array(sorted.prefix(3))
        popularVODs = Array(sorted.prefix(15))
        // "Recently added" — last 15 items in fetch order (server usually returns newest last)
        recentVODs = Array(allVODs.suffix(15).reversed())
        series = Array(allSeries.prefix(10))
        isLoading = false

        startHeroRotation()
    }

    private func startHeroRotation() {
        guard heroBannerVODs.count > 1 else { return }
        heroRotationTask?.cancel()
        heroRotationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        heroBannerIndex = (heroBannerIndex + 1) % heroBannerVODs.count
                    }
                }
            }
        }
    }
}

// MARK: - VODCard

private struct VODCard: View {
    let vod: XstreamVOD
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color(hex: "#2A2A2A")
                        .overlay(
                            Image(systemName: "film")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.3))
                        )
                }
            }
            .frame(width: 160, height: 240)
            .clipped()

            if isHovering {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    if let rating = vod.rating, !rating.isEmpty, Double(rating) != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(rating)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(vod.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(8)
                .transition(.opacity)
            }
        }
        .frame(width: 160, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .shadow(color: .black.opacity(isHovering ? 0.5 : 0.2), radius: isHovering ? 12 : 4)
        .animation(.easeInOut(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - SeriesCard

private struct SeriesCard: View {
    let series: XstreamSeries
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color(hex: "#2A2A2A")
                        .overlay(
                            Image(systemName: "tv")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.3))
                        )
                }
            }
            .frame(width: 160, height: 240)
            .clipped()

            if isHovering {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(series.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .frame(width: 160, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .shadow(color: .black.opacity(isHovering ? 0.5 : 0.2), radius: isHovering ? 12 : 4)
        .animation(.easeInOut(duration: 0.18), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - WelcomeView

/// Shown instead of HomeView when no playlist has been added yet.
struct WelcomeView: View {
    @State private var showAddPlaylist = false
    @State private var gradientOffset: CGFloat = 0
    @Environment(\.modelContext) private var modelContext
    @State private var addedPlaylist: PlaylistRecord?

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
        .background(Color(hex: "#0D0D0D"))
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

// MARK: - Color(hex:) helper

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let int = UInt64(hex, radix: 16) ?? 0
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
