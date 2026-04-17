import SwiftUI
import SwiftData
import AetherCore
import AetherUI

#if os(iOS)
/// Channel list view for iOS.
struct IOSChannelListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var epgStore: EPGStore

    let playlist: PlaylistRecord
    @Binding var selectedChannel: Channel?
    @ObservedObject var player: PlayerCore

    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if filteredChannels.isEmpty && !isRefreshing {
                EmptyStateView(
                    title: "No Channels",
                    systemImage: "antenna.radiowaves.left.and.right",
                    message: searchText.isEmpty ? "Pull to refresh." : "No results for \"\(searchText)\"."
                )
            } else {
                List(filteredChannels, id: \.id) { record in
                    if let channel = record.toChannel() {
                        Button {
                            selectAndPlay(channel)
                        } label: {
                            ChannelRowView(
                                channel: channel,
                                isSelected: player.currentChannel == channel
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .refreshable { await refresh() }
            }
        }
        .searchable(text: $searchText, prompt: "Search channels")
        .navigationTitle(playlist.name)
        .task {
            if playlist.channels.isEmpty { await refresh() }
        }
    }

    private var filteredChannels: [ChannelRecord] {
        let all = playlist.channels.sorted { $0.sortIndex < $1.sortIndex }
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func selectAndPlay(_ channel: Channel) {
        selectedChannel = channel
        let flat = filteredChannels.compactMap { $0.toChannel() }
        player.channelList = flat
        player.play(channel)
    }

    @MainActor
    private func refresh() async {
        guard let url = playlist.effectiveURL else {
            errorMessage = "Invalid playlist URL"
            return
        }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            let service = PlaylistService()
            let channels = try await service.fetchChannels(from: url, forceRefresh: true)
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
#endif
