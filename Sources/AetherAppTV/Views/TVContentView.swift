     1|import SwiftUI
     2|import AVKit
     3|import SwiftData
     4|import AetherCore
     5|import AetherUI
     6|
     7|#if os(tvOS)
     8|/// Root view for tvOS — full-screen player with channel list overlay.
     9|struct TVContentView: View {
    10|    @Bindable var playerCore: PlayerCore
    11|    @EnvironmentObject private var epgStore: EPGStore
    12|
    13|    @Query private var playlists: [PlaylistRecord]
    14|
    15|    @State private var selectedPlaylist: PlaylistRecord?
    16|    @State private var showChannelList = false
    17|
    18|    var body: some View {
    19|        ZStack {
    20|            TVVideoPlayer(avPlayer: playerCore.player)
    21|                .ignoresSafeArea()
    22|
    23|            if showChannelList {
    24|                TVChannelPickerOverlay(
    25|                    playlists: playlists,
    26|                    selectedPlaylist: $selectedPlaylist,
    27|                    player: playerCore,
    28|                    isVisible: $showChannelList
    29|                )
    30|                .transition(.move(edge: .leading))
    31|            }
    32|
    33|            if !showChannelList {
    34|                VStack {
    35|                    Spacer()
    36|                    PlayerControlsView(player: playerCore)
    37|                }
    38|                .transition(.move(edge: .bottom))
    39|            }
    40|        }
    41|        .animation(.easeInOut(duration: 0.25), value: showChannelList)
    42|        .onPlayPauseCommand { playerCore.togglePlayPause() }
    43|        .onMoveCommand { direction in
    44|            if direction == .left { showChannelList = true }
    45|        }
    46|        .onExitCommand {
    47|            if showChannelList { showChannelList = false }
    48|        }
    49|        .task {
    50|            if selectedPlaylist == nil { selectedPlaylist = playlists.first }
    51|            if let last = playerCore.restoreLastChannel() { playerCore.play(last) }
    52|        }
    53|        .onChange(of: selectedPlaylist) { _, newPlaylist in
    54|            guard let playlist = newPlaylist else { return }
    55|            playerCore.currentXstreamCredentials = playlist.xstreamCredentials
    56|            Task { await epgStore.loadGuide(for: playlist) }
    57|        }
    58|    }
    59|}
    60|
    61|// MARK: - TVChannelPickerOverlay
    62|
    63|private struct TVChannelPickerOverlay: View {
    64|    let playlists: [PlaylistRecord]
    65|    @Binding var selectedPlaylist: PlaylistRecord?
    66|    @Bindable var player: PlayerCore
    67|    @Binding var isVisible: Bool
    68|
    69|    @State private var channels: [Channel] = []
    70|    @State private var searchText = ""
    71|    @State private var isLoading = false
    72|
    73|    private var filteredChannels: [Channel] {
    74|        guard !searchText.isEmpty else { return channels }
    75|        return channels.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    76|    }
    77|
    78|    var body: some View {
    79|        HStack(spacing: 0) {
    80|            // Sidebar: playlist list
    81|            VStack(alignment: .leading, spacing: 0) {
    82|                Text("Playlists")
    83|                    .font(.headline)
    84|                    .padding(.horizontal)
    85|                    .padding(.top, 20)
    86|                    .padding(.bottom, 8)
    87|
    88|                List(playlists, selection: $selectedPlaylist) { playlist in
    89|                    Text(playlist.name).font(.body).tag(playlist)
    90|                }
    91|                .listStyle(.grouped)
    92|            }
    93|            .frame(width: 280)
    94|            .background(.ultraThinMaterial)
    95|
    96|            Divider()
    97|
    98|            // Channel list
    99|            VStack(alignment: .leading, spacing: 0) {
   100|                if let playlist = selectedPlaylist {
   101|                    Text(playlist.name)
   102|                        .font(.headline)
   103|                        .padding(.horizontal)
   104|                        .padding(.top, 20)
   105|                        .padding(.bottom, 8)
   106|                }
   107|
   108|                if filteredChannels.isEmpty && !isLoading {
   109|                    EmptyStateView(
   110|                        title: "No Channels",
   111|                        systemImage: "antenna.radiowaves.left.and.right",
   112|                        message: selectedPlaylist == nil ? "Select a playlist." : "No channels found."
   113|                    )
   114|                } else {
   115|                    List(filteredChannels, id: \.id) { channel in
   116|                        Button {
   117|                            player.channelList = filteredChannels
   118|                            player.play(channel)
   119|                            isVisible = false
   120|                        } label: {
   121|                            ChannelRowView(
   122|                                channel: channel,
   123|                                isSelected: player.currentChannel == channel
   124|                            )
   125|                        }
   126|                        .buttonStyle(.plain)
   127|                    }
   128|                    .listStyle(.grouped)
   129|                }
   130|            }
   131|            .frame(maxWidth: .infinity)
   132|            .background(.ultraThinMaterial)
   133|
   134|            Spacer()
   135|        }
   136|        .frame(maxWidth: 780, maxHeight: .infinity, alignment: .leading)
   137|        .background(.ultraThinMaterial.opacity(0.95))
   138|        .task(id: selectedPlaylist?.id) {
   139|            await loadChannels()
   140|        }
   141|    }
   142|
   143|    @MainActor
   144|    private func loadChannels() async {
   145|        guard let playlist = selectedPlaylist else { channels = []; return }
   146|        isLoading = true
   147|        defer { isLoading = false }
   148|
   149|        // Load from cache first
   150|        let cached = await ChannelCache.shared.load(playlistID: playlist.id)
   151|        if !cached.isEmpty { channels = cached; return }
   152|
   153|        // Fetch from network
   154|        do {
   155|            if playlist.playlistType == .xtream, let creds = playlist.xstreamCredentials {
   156|                channels = try await XstreamService(credentials: creds).channels()
   157|            } else if let url = playlist.effectiveURL {
   158|                channels = try await PlaylistService().fetchChannels(from: url, forceRefresh: true)
   159|            }
   160|            let fetched = channels
   161|            let id = playlist.id
   162|            Task.detached(priority: .background) {
   163|                try? await ChannelCache.shared.save(channels: fetched, playlistID: id)
   164|            }
   165|        } catch {
   166|            channels = []
   167|        }
   168|    }
   169|}
   170|
   171|// MARK: - TVVideoPlayer
   172|
   173|private struct TVVideoPlayer: UIViewControllerRepresentable {
   174|    let avPlayer: AVPlayer
   175|
   176|    func makeUIViewController(context: Context) -> AVPlayerViewController {
   177|        let vc = AVPlayerViewController()
   178|        vc.player = avPlayer
   179|        vc.allowsPictureInPicturePlayback = false
   180|        vc.showsPlaybackControls = false
   181|        return vc
   182|    }
   183|
   184|    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
   185|        if uiViewController.player !== avPlayer { uiViewController.player = avPlayer }
   186|    }
   187|}
   188|#endif
   189|