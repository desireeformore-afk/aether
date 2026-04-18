import SwiftUI
import SwiftData
import AetherCore
import AetherUI

#if os(iOS)
/// Root view for iOS — tab-based navigation.
struct IOSContentView: View {
    @Bindable var playerCore: PlayerCore
    @EnvironmentObject private var epgStore: EPGStore

    @State private var selectedPlaylist: PlaylistRecord?
    @State private var selectedChannel: Channel?

    var body: some View {
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
        .onChange(of: selectedPlaylist) { _, newPlaylist in
            guard let playlist = newPlaylist else {
                playerCore.currentXstreamCredentials = nil
                return
            }
            playerCore.currentXstreamCredentials = playlist.xstreamCredentials
            Task { await epgStore.loadGuide(for: playlist) }
        }
    }
}
#endif
