import SwiftUI
import SwiftData
import AetherCore
import AetherUI

#if os(iOS)
/// Channel list view for iOS — in-memory channels from ChannelCache.
struct IOSChannelListView: View {
    @EnvironmentObject private var epgStore: EPGStore

    let playlist: PlaylistRecord
    @Binding var selectedChannel: Channel?
    @ObservedObject var player: PlayerCore

    @State private var channels: [Channel] = []
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
                List(filteredChannels, id: \.id) { channel in
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
                .listStyle(.plain)
                .refreshable { await refresh() }
            }
        }
        .searchable(text: $searchText, prompt: "Search channels")
        .navigationTitle(playlist.name)
        .task {
            await loadFromCache()
            let cacheAge = await ChannelCache.shared.lastModified(playlistID: playlist.id)
                .map { Date().timeIntervalSince($0) } ?? .infinity
            if channels.isEmpty || cacheAge > 3600 {
                await refresh()
            }
        }
    }

    private var filteredChannels: [Channel] {
        guard !searchText.isEmpty else { return channels }
        return channels.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func selectAndPlay(_ channel: Channel) {
        selectedChannel = channel
        Task { @MainActor in
            player.channelList = filteredChannels
            player.play(channel)
        }
    }

    @MainActor
    private func loadFromCache() async {
        let cached = await ChannelCache.shared.load(playlistID: playlist.id)
        if !cached.isEmpty { channels = cached }
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            let fetched: [Channel]
            if playlist.playlistType == .xtream, let creds = playlist.xstreamCredentials {
                let service = XstreamService(credentials: creds)
                fetched = try await service.channels()
            } else {
                guard let url = playlist.effectiveURL else {
                    errorMessage = "Invalid playlist URL"; return
                }
                fetched = try await PlaylistService().fetchChannels(from: url, forceRefresh: true)
            }
            channels = fetched
            playlist.lastRefreshed = Date()
            let id = playlist.id
            Task.detached(priority: .background) {
                try? await ChannelCache.shared.save(channels: fetched, playlistID: id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
