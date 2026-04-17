import SwiftUI
import AVKit
import AetherCore
import AetherUI

#if os(tvOS)
/// Root view for tvOS — full-screen player with channel list overlay.
struct TVContentView: View {
    @ObservedObject var playerCore: PlayerCore
    @EnvironmentObject private var epgStore: EPGStore

    @State private var selectedPlaylist: PlaylistRecord?
    @State private var showChannelList = false

    var body: some View {
        ZStack {
            // Full-screen video player
            TVVideoPlayer(avPlayer: playerCore.player)
                .ignoresSafeArea()

            // Overlay controls
            VStack {
                Spacer()
                PlayerControlsView(player: playerCore)
            }
        }
        .onPlayPauseCommand {
            playerCore.togglePlayPause()
        }
    }
}

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
