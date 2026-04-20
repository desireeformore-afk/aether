import SwiftUI
import SwiftData
import AetherCore

// MARK: - App Section

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case live = "Na żywo"
    case movies = "Filmy"
    case series = "Seriale"
    case search = "Szukaj"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:   return "house.fill"
        case .live:   return "tv.fill"
        case .movies: return "film.fill"
        case .series: return "play.square.stack.fill"
        case .search: return "magnifyingglass"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(EPGStore.self) private var epgStore
    @Environment(NetworkMonitorService.self) private var networkMonitor
    @Environment(ThemeService.self) private var themeService
    @Environment(\.modelContext) private var modelContext
    @Bindable var playerCore: PlayerCore

    @State private var selectedSection: AppSection = .home
    @State private var selectedPlaylist: PlaylistRecord?
    @State private var isFullscreenPlayer = false
    @StateObject private var homeViewModel = HomeViewModel()
    @Query private var allPlaylists: [PlaylistRecord]

    #if os(macOS)
    @State private var showCommandPalette = false
    @State private var searchActivationToken: Int = 0
    private let keyboardHandler: KeyboardShortcutHandler
    #endif

    @AppStorage("preferredColorScheme") private var preferredScheme: String = "auto"

    private var resolvedColorScheme: ColorScheme? {
        switch preferredScheme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    private var activeCredentials: XstreamCredentials? {
        (selectedPlaylist ?? allPlaylists.first)?.xstreamCredentials
    }

    init(playerCore: PlayerCore) {
        self.playerCore = playerCore
        #if os(macOS)
        self.keyboardHandler = KeyboardShortcutHandler(playerCore: playerCore)
        #endif
    }

    var body: some View {
        Group {
            if allPlaylists.isEmpty {
                WelcomeView { playlist in
                    selectedPlaylist = playlist
                    playerCore.currentXstreamCredentials = playlist.xstreamCredentials
                }
            } else if isFullscreenPlayer {
                PlayerView(player: playerCore)
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        Button(action: { isFullscreenPlayer = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(20)
                        }
                        .buttonStyle(.plain)
                    }
            } else {
                mainLayout
            }
        }
        .preferredColorScheme(resolvedColorScheme)
        .onChange(of: playerCore.state) { _, newState in
            if case .playing = newState { isFullscreenPlayer = true }
        }
        .onChange(of: selectedPlaylist) { _, newPlaylist in
            guard let playlist = newPlaylist else {
                playerCore.currentXstreamCredentials = nil
                return
            }
            playerCore.currentXstreamCredentials = playlist.xstreamCredentials
            Task { await epgStore.loadGuide(for: playlist) }
        }
        .onAppear {
            #if os(macOS)
            setupKeyboardHandlerCallbacks()
            keyboardHandler.startMonitoring()
            #endif
            if let channel = playerCore.restoreLastChannel() {
                playerCore.play(channel)
            }
        }
        .onDisappear {
            #if os(macOS)
            keyboardHandler.stopMonitoring()
            #endif
        }
        #if os(macOS)
        .animation(.spring(duration: 0.2), value: showCommandPalette)
        .onKeyPress(.init("k"), phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            showCommandPalette.toggle()
            return .handled
        }
        #endif
    }

    // MARK: - Main NavigationSplitView layout

    @ViewBuilder
    private var mainLayout: some View {
        ZStack {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                sidebarContent
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)

            // Network status banner
            VStack {
                NetworkStatusBanner(networkMonitor: networkMonitor)
                Spacer()
            }
            .ignoresSafeArea()

            // Command palette overlay
            #if os(macOS)
            if showCommandPalette {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }
                    CommandPaletteView(
                        isPresented: $showCommandPalette,
                        player: playerCore,
                        channels: playerCore.channelList
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            #endif
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(.sRGB, red: 0.08, green: 0.08, blue: 0.08, opacity: 1))
            .accentColor(.blue)

            // Mini player bar at bottom of sidebar
            if playerCore.state == .playing, let channel = playerCore.currentChannel {
                miniPlayerBar(channel: channel)
            }
        }
        .background(Color(.sRGB, red: 0.08, green: 0.08, blue: 0.08, opacity: 1))
    }

    private func miniPlayerBar(channel: Channel) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: channel.logoURL) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: Color(.sRGB, red: 0.2, green: 0.2, blue: 0.2, opacity: 1)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(channel.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { playerCore.togglePlayPause() }) {
                Image(systemName: playerCore.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(.sRGB, red: 0.12, green: 0.12, blue: 0.12, opacity: 1))
        .onTapGesture { isFullscreenPlayer = true }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch selectedSection {
            case .home:
                if let creds = activeCredentials {
                    HomeView(viewModel: homeViewModel, player: playerCore, credentials: creds)
                        .onAppear { homeViewModel.load(credentials: creds) }
                } else {
                    noPlaylistPrompt
                }
            case .live:
                if let playlist = selectedPlaylist ?? allPlaylists.first {
                    ChannelListView(
                        playlist: playlist,
                        selectedChannel: .constant(nil),
                        player: playerCore
                    )
                } else {
                    noPlaylistPrompt
                }
            case .movies:
                if let creds = activeCredentials {
                    VODBrowserView(homeViewModel: homeViewModel, player: playerCore, credentials: creds)
                } else {
                    noPlaylistPrompt
                }
            case .series:
                if let creds = activeCredentials {
                    SeriesBrowserView(homeViewModel: homeViewModel, player: playerCore, credentials: creds)
                } else {
                    noPlaylistPrompt
                }
            case .search:
                if let creds = activeCredentials {
                    GlobalContentSearchView(
                        service: homeViewModel.sharedService,
                        credentials: creds,
                        player: playerCore,
                        homeViewModel: homeViewModel
                    )
                } else {
                    noPlaylistPrompt
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var noPlaylistPrompt: some View {
        ContentUnavailableView(
            "Brak playlisty",
            systemImage: "tv.slash",
            description: Text("Dodaj playlistę w ustawieniach")
        )
    }

    // MARK: - Keyboard handler (macOS)

    #if os(macOS)
    private func setupKeyboardHandlerCallbacks() {
        keyboardHandler.onClosePanel = {}
        keyboardHandler.onActivateSearch = {
            selectedSection = .search
            searchActivationToken += 1
        }
        keyboardHandler.onToggleFavorite = {
            guard let channel = playerCore.currentChannel else { return }
            toggleFavorite(channel: channel)
        }
        keyboardHandler.onRestoreLastChannel = {
            if let channel = playerCore.restoreLastChannel() {
                playerCore.play(channel)
            }
        }
    }

    private func toggleFavorite(channel: Channel) {
        let channelID = channel.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.channelID == channelID })
        )
        if let record = existing?.first {
            modelContext.delete(record)
        } else {
            let record = FavoriteRecord(channel: channel)
            modelContext.insert(record)
        }
        try? modelContext.save()
    }
    #endif
}
