import SwiftUI
import SwiftData
import AetherCore

/// Root view: NavigationSplitView with playlist sidebar, channel list, and player.
struct ContentView: View {
    @EnvironmentObject private var epgStore: EPGStore
    @StateObject private var player = PlayerCore()
    @State private var selectedPlaylist: PlaylistRecord?
    @State private var selectedChannel: Channel?
    @State private var showVODBrowser = false

    var body: some View {
        NavigationSplitView {
            PlaylistSidebar(selectedPlaylist: $selectedPlaylist)
        } content: {
            if let playlist = selectedPlaylist {
                ChannelListView(
                    playlist: playlist,
                    selectedChannel: $selectedChannel,
                    player: player
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
                                VODBrowserView(credentials: creds, player: player)
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
            PlayerView(player: player)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.aetherBackground)
        .onChange(of: selectedPlaylist) { _, newPlaylist in
            guard let playlist = newPlaylist else { return }
            Task { await epgStore.loadGuide(for: playlist) }
        }
    }
}
