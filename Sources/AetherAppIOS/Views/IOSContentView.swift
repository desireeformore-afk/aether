     1|import SwiftUI
     2|import SwiftData
     3|import AetherCore
     4|import AetherUI
     5|
     6|#if os(iOS)
     7|/// Root view for iOS — tab-based navigation.
     8|struct IOSContentView: View {
     9|    @Bindable var playerCore: PlayerCore
    10|    @EnvironmentObject private var epgStore: EPGStore
    11|
    12|    @State private var selectedPlaylist: PlaylistRecord?
    13|    @State private var selectedChannel: Channel?
    14|
    15|    var body: some View {
    16|        TabView {
    17|            NavigationStack {
    18|                IOSPlaylistSidebar(selectedPlaylist: $selectedPlaylist)
    19|                    .navigationTitle("Playlists")
    20|            }
    21|            .tabItem { Label("Playlists", systemImage: "list.bullet") }
    22|
    23|            NavigationStack {
    24|                if let playlist = selectedPlaylist {
    25|                    IOSChannelListView(
    26|                        playlist: playlist,
    27|                        selectedChannel: $selectedChannel,
    28|                        player: playerCore
    29|                    )
    30|                } else {
    31|                    EmptyStateView(
    32|                        title: "No Playlist",
    33|                        systemImage: "list.bullet.rectangle",
    34|                        message: "Select a playlist first."
    35|                    )
    36|                }
    37|            }
    38|            .tabItem { Label("Channels", systemImage: "antenna.radiowaves.left.and.right") }
    39|
    40|            IOSPlayerView(player: playerCore)
    41|                .tabItem { Label("Player", systemImage: "play.circle") }
    42|        }
    43|        .onChange(of: selectedPlaylist) { _, newPlaylist in
    44|            guard let playlist = newPlaylist else {
    45|                playerCore.currentXstreamCredentials = nil
    46|                return
    47|            }
    48|            playerCore.currentXstreamCredentials = playlist.xstreamCredentials
    49|            Task { await epgStore.loadGuide(for: playlist) }
    50|        }
    51|    }
    52|}
    53|#endif
    54|