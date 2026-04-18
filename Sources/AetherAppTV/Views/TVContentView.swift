import SwiftUI
import AVKit
import SwiftData
import AetherCore
import AetherUI

#if os(tvOS)
/// Root view for tvOS — full-screen player with channel list overlay.
struct TVContentView: View {
    @Bindable var playerCore: PlayerCore
    @EnvironmentObject private var epgStore: EPGStore

    @Query private var playlists: [PlaylistRecord]

    @State private var selectedPlaylist: PlaylistRecord?
    @State private var showChannelList = false

    var body: some View {
        ZStack {
            TVVideoPlayer(avPlayer: playerCore.player)
                .ignoresSafeArea()

            if showChannelList {
                TVChannelPickerOverlay(
                    playlists: playlists,
                    selectedPlaylist: $selectedPlaylist,
                    player: playerCore,
                    isVisible: $showChannelList
                )
                .transition(.move(edge: .leading))
            }

            if !showChannelList {
                VStack {
                    Spacer()
                    PlayerControlsView(player: playerCore)
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showChannelList)
        .onPlayPauseCommand { playerCore.togglePlayPause() }
        .onMoveCommand { direction in
            if direction == .left { showChannelList = true }
        }
        .onExitCommand {
            if showChannelList { showChannelList = false }
        }
        .task {
            if selectedPlaylist == nil { selectedPlaylist = playlists.first }
            if let last = playerCore.restoreLastChannel() { playerCore.play(last) }
        }
        .onChange(of: selectedPlaylist) { _, newPlaylist in
            guard let playlist = newPlaylist else { return }
            playerCore.currentXstreamCredentials = playlist.xstreamCredentials
            Task { await epgStore.loadGuide(for: playlist) }
        }
    }
}

// MARK: - TVChannelPickerOverlay

private struct TVChannelPickerOverlay: View {
    let playlists: [PlaylistRecord]
    @Binding var selectedPlaylist: PlaylistRecord?
    @Bindable var player: PlayerCore
    @Binding var isVisible: Bool

    @State private var channels: [Channel] = []
    @State private var searchText = ""
    @State private var isLoading = false

    private var filteredChannels: [Channel] {
        guard !searchText.isEmpty else { return channels }
        return channels.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar: playlist list
            VStack(alignment: .leading, spacing: 0) {
                Text("Playlists")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 8)

                List(playlists, selection: $selectedPlaylist) { playlist in
                    Text(playlist.name).font(.body).tag(playlist)
                }
                .listStyle(.grouped)
            }
            .frame(width: 280)
            .background(.ultraThinMaterial)

            Divider()

            // Channel list
            VStack(alignment: .leading, spacing: 0) {
                if let playlist = selectedPlaylist {
                    Text(playlist.name)
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                }

                if filteredChannels.isEmpty && !isLoading {
                    EmptyStateView(
                        title: "No Channels",
                        systemImage: "antenna.radiowaves.left.and.right",
                        message: selectedPlaylist == nil ? "Select a playlist." : "No channels found."
                    )
                } else {
                    List(filteredChannels, id: \.id) { channel in
                        Button {
                            player.channelList = filteredChannels
                            player.play(channel)
                            isVisible = false
                        } label: {
                            ChannelRowView(
                                channel: channel,
                                isSelected: player.currentChannel == channel
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.grouped)
                }
            }
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)

            Spacer()
        }
        .frame(maxWidth: 780, maxHeight: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.95))
        .task(id: selectedPlaylist?.id) {
            await loadChannels()
        }
    }

    @MainActor
    private func loadChannels() async {
        guard let playlist = selectedPlaylist else { channels = []; return }
        isLoading = true
        defer { isLoading = false }

        // Load from cache first
        let cached = await ChannelCache.shared.load(playlistID: playlist.id)
        if !cached.isEmpty { channels = cached; return }

        // Fetch from network
        do {
            if playlist.playlistType == .xtream, let creds = playlist.xstreamCredentials {
                channels = try await XstreamService(credentials: creds).channels()
            } else if let url = playlist.effectiveURL {
                channels = try await PlaylistService().fetchChannels(from: url, forceRefresh: true)
            }
            let fetched = channels
            let id = playlist.id
            Task.detached(priority: .background) {
                try? await ChannelCache.shared.save(channels: fetched, playlistID: id)
            }
        } catch {
            channels = []
        }
    }
}

// MARK: - TVVideoPlayer

private struct TVVideoPlayer: UIViewControllerRepresentable {
    let avPlayer: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = avPlayer
        vc.allowsPictureInPicturePlayback = false
        vc.showsPlaybackControls = false
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== avPlayer { uiViewController.player = avPlayer }
    }
}
#endif
