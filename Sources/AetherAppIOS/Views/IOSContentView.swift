import SwiftUI
import SwiftData
import AetherCore
import AetherUI

#if os(iOS)
/// Root view for iOS — tab-based on iPhone, split view on iPad.
struct IOSContentView: View {
    @Bindable var playerCore: PlayerCore
    @Environment(EPGStore.self) private var epgStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedPlaylist: PlaylistRecord?
    @State private var selectedChannel: Channel?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                tabLayout
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
    }

    @ViewBuilder
    private var splitLayout: some View {
        NavigationSplitView {
            IOSPlaylistSidebar(selectedPlaylist: $selectedPlaylist)
        } content: {
            if let playlist = selectedPlaylist {
                IOSChannelListView(
                    playlist: playlist,
                    selectedChannel: $selectedChannel,
                    player: playerCore
                )
            } else {
                EmptyStateView(
                    title: "No Playlist",
                    systemImage: "list.bullet.rectangle",
                    message: "Select a playlist first."
                )
            }
        } detail: {
            IOSPlayerView(player: playerCore)
        }
    }

    @ViewBuilder
    private var tabLayout: some View {
        TabView {
            NavigationStack {
                IOSPlaylistSidebar(selectedPlaylist: $selectedPlaylist)
                    .navigationTitle("Playlists")
            }
            .tabItem { Label("Playlists", systemImage: "list.bullet") }

            NavigationStack {
                if let playlist = selectedPlaylist {
                    IOSChannelListView(
                        playlist: playlist,
                        selectedChannel: $selectedChannel,
                        player: playerCore
                    )
                } else {
                    EmptyStateView(
                        title: "No Playlist",
                        systemImage: "list.bullet.rectangle",
                        message: "Select a playlist first."
                    )
                }
            }
            .tabItem { Label("Channels", systemImage: "antenna.radiowaves.left.and.right") }

            IOSPlayerView(player: playerCore)
                .tabItem { Label("Player", systemImage: "play.circle") }
        }
    }
}
#endif
