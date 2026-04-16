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
                Label(playlist.name, systemImage: "play.rectangle.on.rectangle")
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
            AddPlaylistSheet { name, urlString in
                addPlaylist(name: name, urlString: urlString)
            }
        }
    }

    private func addPlaylist(name: String, urlString: String) {
        let record = PlaylistRecord(name: name, urlString: urlString)
        modelContext.insert(record)
        selectedPlaylist = record
    }

    private func deletePlaylists(at offsets: IndexSet) {
        for index in offsets {
            let playlist = playlists[index]
            if selectedPlaylist == playlist { selectedPlaylist = nil }
            modelContext.delete(playlist)
        }
    }
}
