import SwiftUI
import SwiftData
import AetherCore

/// Left sidebar: list of saved playlists, add/delete actions.
struct PlaylistSidebar: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaylistRecord.name) private var playlists: [PlaylistRecord]

    @Binding var selectedPlaylist: PlaylistRecord?
    @State private var showAddSheet = false

    var body: some View {
        List(selection: $selectedPlaylist) {
            ForEach(playlists) { playlist in
                PlaylistRow(playlist: playlist)
                    .tag(playlist)
            }
            .onDelete(perform: deletePlaylists)
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .help("Add Playlist")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPlaylistSheet { record in
                selectedPlaylist = record
            }
        }
    }

    private func deletePlaylists(at offsets: IndexSet) {
        for index in offsets {
            let playlist = playlists[index]
            if selectedPlaylist == playlist { selectedPlaylist = nil }
            modelContext.delete(playlist)
        }
    }
}

/// Single row in the playlist list.
private struct PlaylistRow: View {
    let playlist: PlaylistRecord

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.aetherBody)
                HStack(spacing: 4) {
                    Image(systemName: playlist.playlistType == .xtream ? "server.rack" : "link")
                        .font(.system(size: 9))
                    Text(playlist.playlistType == .xtream ? "Xtream Codes" : "M3U")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "play.rectangle.on.rectangle")
                .foregroundStyle(Color.aetherPrimary)
        }
    }
}
