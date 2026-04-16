import SwiftUI
import SwiftData
import AetherCore

/// Left sidebar: list of saved playlists with add/delete/reorder and active indicator.
struct PlaylistSidebar: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaylistRecord.sortIndex) private var playlists: [PlaylistRecord]

    @Binding var selectedPlaylist: PlaylistRecord?
    @State private var showAddSheet = false
    @State private var isEditMode = false

    var body: some View {
        List(selection: $selectedPlaylist) {
            ForEach(playlists) { playlist in
                PlaylistRow(playlist: playlist, isActive: selectedPlaylist == playlist)
                    .tag(playlist)
            }
            .onDelete(perform: deletePlaylists)
            .onMove(perform: movePlaylists)
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .help("Add Playlist  ⌘N")
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(action: { isEditMode.toggle() }) {
                    Text(isEditMode ? "Done" : "Edit")
                        .font(.aetherBody)
                }
                .help(isEditMode ? "Finish editing" : "Reorder or delete playlists")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPlaylistSheet { record in
                // Assign sort index at end of list
                record.sortIndex = (playlists.last?.sortIndex ?? -1) + 1
                selectedPlaylist = record
            }
        }
        .onChange(of: playlists) { _, newList in
            // Auto-select first playlist if none selected
            if selectedPlaylist == nil, let first = newList.first {
                selectedPlaylist = first
            }
        }
    }

    private func deletePlaylists(at offsets: IndexSet) {
        for index in offsets {
            let playlist = playlists[index]
            if selectedPlaylist == playlist { selectedPlaylist = nil }
            modelContext.delete(playlist)
        }
        reindex()
    }

    private func movePlaylists(from source: IndexSet, to destination: Int) {
        var reordered = playlists
        reordered.move(fromOffsets: source, toOffset: destination)
        for (idx, playlist) in reordered.enumerated() {
            playlist.sortIndex = idx
        }
    }

    private func reindex() {
        for (idx, playlist) in playlists.enumerated() {
            playlist.sortIndex = idx
        }
    }
}

// MARK: - PlaylistRow

/// Single row in the playlist sidebar.
fileprivate struct PlaylistRow: View {
    let playlist: PlaylistRecord
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.aetherPrimary : Color.aetherSurface)
                    .frame(width: 36, height: 36)
                Image(systemName: playlist.playlistType == .xtream ? "server.rack" : "play.rectangle.on.rectangle")
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? .white : Color.aetherText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.aetherBody)
                    .foregroundStyle(Color.aetherText)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(playlist.playlistType == .xtream ? "Xtream Codes" : "M3U")
                        .font(.system(size: 10))
                    if let refreshed = playlist.lastRefreshed {
                        Text("·")
                        Text(refreshed, style: .relative)
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.aetherPrimary)
                    .font(.system(size: 14))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
