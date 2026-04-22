import SwiftUI
import SwiftData
import AetherCore
#if os(macOS)
import AppKit
#endif

// MARK: - Menu-bar navigation notification names

extension Notification.Name {
    static let aetherNavigateFavorites  = Notification.Name("aetherNavigateFavorites")
    static let aetherNavigateSearch     = Notification.Name("aetherNavigateSearch")
    static let aetherNavigateHistory    = Notification.Name("aetherNavigateHistory")
    static let aetherNavigateLive       = Notification.Name("aetherNavigateLive")
    static let aetherRefreshPlaylist    = Notification.Name("aetherRefreshPlaylist")
}

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

    @AppStorage("appearanceMode") private var storedAppearanceMode: String = AppearanceMode.system.rawValue
    @State private var showLanguagePicker = false
    @State private var pendingSearchQuery: String?
    @State private var pendingDeepLinkURL: URL?

    private var resolvedColorScheme: ColorScheme? {
        AppearanceMode(rawValue: storedAppearanceMode)?.colorScheme
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
                    .overlay {
                        if playerCore.state == .loading {
                            ZStack {
                                Color.black.opacity(0.6)
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(1.5)
                                        .tint(.white)
                                    if let channel = playerCore.currentChannel {
                                        Text(channel.name)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
            } else {
                mainLayout
            }
        }
        .preferredColorScheme(resolvedColorScheme)
        .onOpenURL { url in handleDeepLink(url) }
        .onChange(of: playerCore.state) { _, newState in
            switch newState {
            case .loading:
                if !suppressNextFullscreen {
                    isFullscreenPlayer = true
                }
            case .playing:
                if suppressNextFullscreen {
                    suppressNextFullscreen = false
                    isFullscreenPlayer = false
                } else {
                    isFullscreenPlayer = true
                }
            case .error:
                isFullscreenPlayer = false
            case .idle:
                isFullscreenPlayer = false
            case .paused:
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
        .onReceive(NotificationCenter.default.publisher(for: .aetherNavigateFavorites)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { sidebarSelection = .favorites }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aetherNavigateSearch)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { sidebarSelection = .search }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aetherNavigateHistory)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { sidebarSelection = .history }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aetherNavigateLive)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { sidebarSelection = .live }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aetherRefreshPlaylist)) { _ in
            if let creds = activeCredentials {
                homeViewModel.forceReload(credentials: creds)
            }
        }
        .onChange(of: playerCore.channelList) { _, list in
            guard !list.isEmpty, let url = pendingDeepLinkURL else { return }
            pendingDeepLinkURL = nil
            handleDeepLink(url)
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

            if let banner = playerCore.streamErrorBanner {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(banner)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                        Spacer()
                        if let channel = playerCore.currentChannel {
                            Button("Retry") {
                                playerCore.clearStreamErrorBanner()
                                playerCore.play(channel)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.white)
                        }
                        Button("✕") { playerCore.clearStreamErrorBanner() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(12)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: playerCore.streamErrorBanner)
            }
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
                        homeViewModel: homeViewModel,
                        initialQuery: pendingSearchQuery
                    )
                    .onAppear { pendingSearchQuery = nil }
                } else {
                    noPlaylistPrompt
                }
            case .favorites:
                FavoritesView(player: playerCore)
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
        .animation(.easeInOut(duration: 0.2), value: sidebarSelection)
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
        keyboardHandler.onToggleFullscreen = {
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
        keyboardHandler.onRestoreLastChannel = {
            if let channel = playerCore.restoreLastChannel() {
                playerCore.play(channel)
            }
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "aether",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        switch url.host {
        case "play":
            if playerCore.channelList.isEmpty {
                pendingDeepLinkURL = url
                return
            }
            if let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
               let uuid = UUID(uuidString: idString),
               let channel = playerCore.channelList.first(where: { $0.id == uuid }) {
                playerCore.play(channel)
            }
        case "search":
            if let q = components.queryItems?.first(where: { $0.name == "q" })?.value, !q.isEmpty {
                pendingSearchQuery = q
                withAnimation(.easeInOut(duration: 0.15)) { sidebarSelection = .search }
            }
        default:
            break
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
