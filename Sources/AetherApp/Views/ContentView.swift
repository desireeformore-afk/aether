import SwiftUI
import SwiftData
import AetherCore

/// Root view: NavigationSplitView with playlist sidebar, channel list, and player.
struct ContentView: View {
    @EnvironmentObject private var epgStore: EPGStore
    @ObservedObject var playerCore: PlayerCore

    @State private var selectedPlaylist: PlaylistRecord?
    @State private var selectedChannel: Channel?
    @State private var showVODBrowser = false
    @State private var showSeriesBrowser = false

    // Keyboard handler — retained for the lifetime of this view (macOS only)
    #if os(macOS)
    private let keyboardHandler: KeyboardShortcutHandler
    #endif

    init(playerCore: PlayerCore) {
        self.playerCore = playerCore
        #if os(macOS)
        self.keyboardHandler = KeyboardShortcutHandler(playerCore: playerCore)
        #endif
    }

    var body: some View {
        NavigationSplitView {
            PlaylistSidebar(selectedPlaylist: $selectedPlaylist)
        } content: {
            if let playlist = selectedPlaylist {
                ChannelListView(
                    playlist: playlist,
                    selectedChannel: $selectedChannel,
                    player: playerCore
                )
                .toolbar {
                    // VOD button — only for Xtream Codes playlists
                    if playlist.playlistType == .xtream,
                       let creds = playlist.xstreamCredentials {
                        ToolbarItem {
                            Button(action: { showVODBrowser = true }) {
                                Label("VOD", systemImage: "film.stack")
                            }
                            .help("Open VOD Browser")
                            .sheet(isPresented: $showVODBrowser) {
                                VODBrowserView(credentials: creds, player: playerCore)
                            }
                        }
                        ToolbarItem {
                            Button(action: { showSeriesBrowser = true }) {
                                Label("Series", systemImage: "tv.and.mediabox")
                            }
                            .help("Browse Series")
                            .sheet(isPresented: $showSeriesBrowser) {
                                SeriesBrowserView(credentials: creds, player: playerCore)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Playlist Selected",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add a playlist from the sidebar to get started.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.aetherBackground)
            }
        } detail: {
            PlayerView(player: playerCore)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.aetherBackground)
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
            keyboardHandler.startMonitoring()
            #endif
            // Restore last-played channel on relaunch
            if let lastChannel = playerCore.restoreLastChannel() {
                playerCore.play(lastChannel)
            }
        }
        .onDisappear {
            #if os(macOS)
            keyboardHandler.stopMonitoring()
            #endif
        }
    }
}
