import SwiftUI
import SwiftData
import AetherCore

// MARK: - ContentView

struct ContentView: View {
    @Environment(EPGStore.self) private var epgStore
    @Environment(NetworkMonitorService.self) private var networkMonitor
    @Environment(ThemeService.self) private var themeService
    @Environment(\.modelContext) private var modelContext
    @Bindable var playerCore: PlayerCore

    @State private var sidebarSelection: SidebarItem = .home
    @State private var selectedPlaylist: PlaylistRecord?
    @State private var isFullscreenPlayer = false
    @State private var suppressNextFullscreen = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var homeViewModel = HomeViewModel()
    @Query private var allPlaylists: [PlaylistRecord]

    #if os(macOS)
    @State private var showCommandPalette = false
    @State private var searchActivationToken: Int = 0
    private let keyboardHandler: KeyboardShortcutHandler
    #endif

    @AppStorage("preferredColorScheme") private var preferredScheme: String = "auto"
    @State private var showLanguagePicker = false

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

    private var activePlaylistName: String? {
        (selectedPlaylist ?? allPlaylists.first)?.name
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
            switch newState {
            case .loading, .playing:
                if suppressNextFullscreen {
                    suppressNextFullscreen = false
                } else {
                    isFullscreenPlayer = true
                }
            case .idle, .error:
                break
            }
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
                suppressNextFullscreen = true
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
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                SidebarView(selection: $sidebarSelection, playlistName: activePlaylistName)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 240)
                    .toolbar(removing: .sidebarToggle)
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

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        Group {
            switch sidebarSelection {
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
            case .vod:
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
            case .history:
                WatchHistoryView()
            case .settings:
                SettingsView()
                    .overlay(alignment: .topTrailing) {
                        Button {
                            showLanguagePicker.toggle()
                        } label: {
                            Image(systemName: "globe")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(12)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showLanguagePicker, arrowEdge: .leading) {
                            LanguagePickerView()
                                .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                                .onChange(of: homeViewModel.preferredCountry) { _, _ in
                                    homeViewModel.rebuildWithCurrentPreferences()
                                }
                        }
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
            sidebarSelection = .search
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
