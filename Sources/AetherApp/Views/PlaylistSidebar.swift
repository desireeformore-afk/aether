import SwiftUI
import SwiftData
import AetherCore
import AetherUI

/// Left sidebar: recently watched channels + list of saved playlists.
struct PlaylistSidebar: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlaylistRecord.sortIndex) private var playlists: [PlaylistRecord]
    @Query(sort: \WatchHistoryRecord.watchedAt, order: .reverse) private var history: [WatchHistoryRecord]
    @Environment(PlayerCore.self) private var playerCore

    @Binding var selectedPlaylist: PlaylistRecord?
    @State private var showAddSheet = false
    @State private var showHistory = false
    #if os(macOS)
    @State private var showSettings = false
    #endif

    // Deduplicated last 5 unique channels from history
    private var recentChannels: [WatchHistoryRecord] {
        var seen = Set<UUID>()
        return history.filter { seen.insert($0.channelID).inserted }.prefix(5).map { $0 }
    }

    var body: some View {
        listContent
            .navigationTitle("Aether")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showHistory) { historySheet }
            .sheet(isPresented: $showAddSheet) { addPlaylistSheet }
            #if os(macOS)
            .sheet(isPresented: $showSettings) { settingsSheet }
            #endif
            .onChange(of: playlists) { _, newList in
                if selectedPlaylist == nil, let first = newList.first {
                    selectedPlaylist = first
                }
            }
    }
    
    private var listContent: some View {
        List(selection: $selectedPlaylist) {
            // Recently Watched
            if !recentChannels.isEmpty {
                Section("Recently Watched") {
                    ForEach(recentChannels) { record in
                        if let channel = record.toChannel() {
                            RecentChannelRow(record: record)
                                .onTapGesture { playRecent(channel) }
                        }
                    }
                }
            }

            // Playlists
            Section("Playlisty") {
                ForEach(playlists) { playlist in
                    PlaylistRow(playlist: playlist, isActive: selectedPlaylist == playlist)
                        .tag(playlist)
                }
                .onDelete(perform: deletePlaylists)
                .onMove(perform: movePlaylists)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showAddSheet = true }) {
                Image(systemName: "plus")
            }
            .help("Add Playlist  ⌘N")
            .keyboardShortcut("n", modifiers: .command)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button(action: { showHistory = true }) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("Watch History")
            .disabled(history.isEmpty)
        }
        #if os(macOS)
        ToolbarItem(placement: .secondaryAction) {
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
            }
            .help("Settings  ⌘,")
        }
        #endif
    }
    
    private var historySheet: some View {
        WatchHistoryView()
            .environment(playerCore)
    }
    
    private var addPlaylistSheet: some View {
        AddPlaylistSheet { record in
            record.sortIndex = (playlists.last?.sortIndex ?? -1) + 1
            selectedPlaylist = record
        }
    }
    
    #if os(macOS)
    private var settingsSheet: some View {
        SettingsView()
            .frame(width: 600, height: 500)
    }
    #endif

    // MARK: - Actions

    private func playRecent(_ channel: Channel) {
        playerCore.play(channel)
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

// MARK: - RecentChannelRow

private struct RecentChannelRow: View {
    let record: WatchHistoryRecord

    var body: some View {
        HStack(spacing: 8) {
            ChannelLogoView(
                url: record.logoURLString.flatMap { URL(string: $0) },
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(record.channelName)
                    .font(.aetherBody)
                    .foregroundStyle(Color.aetherText)
                    .lineLimit(1)
                Text(record.watchedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - PlaylistRow

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
