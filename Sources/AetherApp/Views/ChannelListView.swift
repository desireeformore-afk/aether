import SwiftUI
import SwiftData
import AetherCore

/// Middle column: channels grouped by `groupTitle`, with search.
struct ChannelListView: View {
    @Environment(\.modelContext) private var modelContext

    let playlist: PlaylistRecord
    @Binding var selectedChannel: Channel?
    @ObservedObject var player: PlayerCore

    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    private var groupedChannels: [(group: String, channels: [ChannelRecord])] {
        let filtered: [ChannelRecord]
        if searchText.isEmpty {
            filtered = playlist.channels
        } else {
            filtered = playlist.channels.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        let sorted = filtered.sorted { $0.sortIndex < $1.sortIndex }
        let grouped = Dictionary(grouping: sorted) { $0.groupTitle }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, channels: $0.value) }
    }

    var body: some View {
        List(selection: $selectedChannel) {
            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            ForEach(groupedChannels, id: \.group) { section in
                Section(section.group) {
                    ForEach(section.channels) { record in
                        if let channel = record.toChannel() {
                            ChannelRow(channel: channel, isPlaying: player.currentChannel == channel)
                                .tag(channel)
                                .onTapGesture { selectAndPlay(channel) }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search channels")
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await refresh() } }) {
                    if isRefreshing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
                .help("Refresh Playlist")
            }
        }
        .task {
            if playlist.channels.isEmpty { await refresh() }
        }
    }

    private func selectAndPlay(_ channel: Channel) {
        selectedChannel = channel
        player.play(channel)
    }

    @MainActor
    private func refresh() async {
        guard let url = playlist.url else {
            errorMessage = "Invalid playlist URL"
            return
        }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            let service = PlaylistService()
            let channels = try await service.fetchChannels(from: url, forceRefresh: true)

            // Replace channels in SwiftData
            for old in playlist.channels { modelContext.delete(old) }
            playlist.channels = channels.enumerated().map { idx, ch in
                ChannelRecord(
                    id: ch.id,
                    name: ch.name,
                    streamURLString: ch.streamURL.absoluteString,
                    logoURLString: ch.logoURL?.absoluteString,
                    groupTitle: ch.groupTitle,
                    epgId: ch.epgId,
                    sortIndex: idx
                )
            }
            playlist.lastRefreshed = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A single row in the channel list.
private struct ChannelRow: View {
    let channel: Channel
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isPlaying ? "waveform" : "play.tv")
                .foregroundStyle(isPlaying ? Color.aetherPrimary : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.aetherBody)
                    .foregroundStyle(isPlaying ? Color.aetherPrimary : Color.aetherText)
                if let group = channel.groupTitle.isEmpty ? nil : channel.groupTitle {
                    Text(group)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
