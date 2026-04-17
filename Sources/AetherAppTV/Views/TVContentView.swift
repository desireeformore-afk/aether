import SwiftUI
import AVKit
import SwiftData
import AetherCore
import AetherUI

#if os(tvOS)
/// Root view for tvOS — full-screen player with channel list overlay.
/// Press Menu/Back to reveal the channel picker.
struct TVContentView: View {
    @ObservedObject var playerCore: PlayerCore
    @EnvironmentObject private var epgStore: EPGStore

    @Query private var playlists: [PlaylistRecord]

    @State private var selectedPlaylist: PlaylistRecord?
    @State private var showChannelList = false

    var body: some View {
        ZStack {
            // Full-screen video player background
            TVVideoPlayer(avPlayer: playerCore.player)
                .ignoresSafeArea()

            // Channel picker overlay — shown on demand
            if showChannelList {
                TVChannelPickerOverlay(
                    playlists: playlists,
                    selectedPlaylist: $selectedPlaylist,
                    player: playerCore,
                    isVisible: $showChannelList
                )
                .transition(.move(edge: .leading))
            }

            // Controls at bottom
            if !showChannelList {
                VStack {
                    Spacer()
                    PlayerControlsView(player: playerCore)
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showChannelList)
        .onPlayPauseCommand {
            playerCore.togglePlayPause()
        }
        .onMoveCommand { direction in
            if direction == .left { showChannelList = true }
        }
        .onExitCommand {
            if showChannelList { showChannelList = false }
        }
        .task {
            // Auto-select first playlist and restore last channel
            if selectedPlaylist == nil { selectedPlaylist = playlists.first }
            if let last = playerCore.restoreLastChannel() {
                playerCore.play(last)
            }
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
    @ObservedObject var player: PlayerCore
    @Binding var isVisible: Bool

    @State private var searchText = ""

    private var channels: [ChannelRecord] {
        guard let playlist = selectedPlaylist else { return [] }
        let all = playlist.channels.sorted { $0.sortIndex < $1.sortIndex }
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                    Text(playlist.name)
                        .font(.body)
                        .tag(playlist)
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

                if channels.isEmpty {
                    EmptyStateView(
                        title: "No Channels",
                        systemImage: "antenna.radiowaves.left.and.right",
                        message: selectedPlaylist == nil ? "Select a playlist." : "No channels found."
                    )
                } else {
                    List(channels, id: \.id) { record in
                        if let channel = record.toChannel() {
                            Button {
                                player.channelList = channels.compactMap { $0.toChannel() }
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
    }
}

// MARK: - TVVideoPlayer

/// Bridges AVPlayer to SwiftUI on tvOS via AVPlayerViewController.
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
        if uiViewController.player !== avPlayer {
            uiViewController.player = avPlayer
        }
    }
}
#endif
