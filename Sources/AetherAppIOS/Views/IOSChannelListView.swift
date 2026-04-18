     1|import SwiftUI
     2|import SwiftData
     3|import AetherCore
     4|import AetherUI
     5|
     6|#if os(iOS)
     7|/// Channel list view for iOS — in-memory channels from ChannelCache.
     8|struct IOSChannelListView: View {
     9|    @EnvironmentObject private var epgStore: EPGStore
    10|
    11|    let playlist: PlaylistRecord
    12|    @Binding var selectedChannel: Channel?
    13|    @Bindable var player: PlayerCore
    14|
    15|    @State private var channels: [Channel] = []
    16|    @State private var searchText = ""
    17|    @State private var isRefreshing = false
    18|    @State private var errorMessage: String?
    19|
    20|    var body: some View {
    21|        Group {
    22|            if filteredChannels.isEmpty && !isRefreshing {
    23|                EmptyStateView(
    24|                    title: "No Channels",
    25|                    systemImage: "antenna.radiowaves.left.and.right",
    26|                    message: searchText.isEmpty ? "Pull to refresh." : "No results for \"\(searchText)\"."
    27|                )
    28|            } else {
    29|                List(filteredChannels, id: \.id) { channel in
    30|                    Button {
    31|                        selectAndPlay(channel)
    32|                    } label: {
    33|                        ChannelRowView(
    34|                            channel: channel,
    35|                            isSelected: player.currentChannel == channel
    36|                        )
    37|                    }
    38|                    .buttonStyle(.plain)
    39|                }
    40|                .listStyle(.plain)
    41|                .refreshable { await refresh() }
    42|            }
    43|        }
    44|        .searchable(text: $searchText, prompt: "Search channels")
    45|        .navigationTitle(playlist.name)
    46|        .task {
    47|            await loadFromCache()
    48|            let cacheAge = await ChannelCache.shared.lastModified(playlistID: playlist.id)
    49|                .map { Date().timeIntervalSince($0) } ?? .infinity
    50|            if channels.isEmpty || cacheAge > 3600 {
    51|                await refresh()
    52|            }
    53|        }
    54|    }
    55|
    56|    private var filteredChannels: [Channel] {
    57|        guard !searchText.isEmpty else { return channels }
    58|        return channels.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    59|    }
    60|
    61|    private func selectAndPlay(_ channel: Channel) {
    62|        selectedChannel = channel
    63|        Task { @MainActor in
    64|            player.channelList = filteredChannels
    65|            player.play(channel)
    66|        }
    67|    }
    68|
    69|    @MainActor
    70|    private func loadFromCache() async {
    71|        let cached = await ChannelCache.shared.load(playlistID: playlist.id)
    72|        if !cached.isEmpty { channels = cached }
    73|    }
    74|
    75|    @MainActor
    76|    private func refresh() async {
    77|        guard !isRefreshing else { return }
    78|        isRefreshing = true
    79|        errorMessage = nil
    80|        defer { isRefreshing = false }
    81|        do {
    82|            let fetched: [Channel]
    83|            if playlist.playlistType == .xtream, let creds = playlist.xstreamCredentials {
    84|                let service = XstreamService(credentials: creds)
    85|                fetched = try await service.channels()
    86|            } else {
    87|                guard let url = playlist.effectiveURL else {
    88|                    errorMessage = "Invalid playlist URL"; return
    89|                }
    90|                fetched = try await PlaylistService().fetchChannels(from: url, forceRefresh: true)
    91|            }
    92|            channels = fetched
    93|            playlist.lastRefreshed = Date()
    94|            let id = playlist.id
    95|            Task.detached(priority: .background) {
    96|                try? await ChannelCache.shared.save(channels: fetched, playlistID: id)
    97|            }
    98|        } catch {
    99|            errorMessage = error.localizedDescription
   100|        }
   101|    }
   102|}
   103|#endif
   104|