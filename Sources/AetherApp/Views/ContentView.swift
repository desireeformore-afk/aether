import SwiftUI
import SwiftData
import AetherCore

/// Root view: NavigationSplitView with playlist sidebar, channel list, and player.
struct ContentView: View {
    @StateObject private var player = PlayerCore()
    @State private var selectedPlaylist: PlaylistRecord?
    @State private var selectedChannel: Channel?

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
    }
}
