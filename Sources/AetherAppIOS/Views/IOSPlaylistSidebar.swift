import SwiftUI
import SwiftData
import AetherCore
import AetherUI

#if os(iOS)
/// Playlist list for iOS — tap to select.
struct IOSPlaylistSidebar: View {
    @Query private var playlists: [PlaylistRecord]
    @Binding var selectedPlaylist: PlaylistRecord?
    @State private var showAddPlaylist = false

    var body: some View {
        List(playlists, selection: $selectedPlaylist) { playlist in
            Button {
                selectedPlaylist = playlist
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.body)
                        .fontWeight(selectedPlaylist?.id == playlist.id ? .semibold : .regular)
                    Text(playlist.playlistType == .xtream ? "Xtream Codes" : "M3U")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddPlaylist = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPlaylist) {
            IOSAddPlaylistSheet()
        }
        .overlay {
            if playlists.isEmpty {
                EmptyStateView(
                    title: "No Playlists",
                    systemImage: "list.bullet.rectangle",
                    message: "Tap + to add your first playlist."
                )
            }
        }
    }
}

/// Minimal add-playlist sheet for iOS.
private struct IOSAddPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var urlString = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist") {
                    TextField("Name", text: $name)
                    TextField("URL", text: $urlString)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Add Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let record = PlaylistRecord(name: name, urlString: urlString)
                        modelContext.insert(record)
                        dismiss()
                    }
                    .disabled(name.isEmpty || urlString.isEmpty)
                }
            }
        }
    }
}
#endif
