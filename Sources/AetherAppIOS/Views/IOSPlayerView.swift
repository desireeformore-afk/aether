import SwiftUI
import AVKit
import AetherCore
import AetherUI

#if os(iOS)
/// Player view for iOS — uses AVPlayerViewController for native controls and PiP.
struct IOSPlayerView: View {
    @Bindable var player: PlayerCore

    var body: some View {
        VStack(spacing: 0) {
            IOSVideoPlayer(avPlayer: player.player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()

            if let channel = player.currentChannel {
                Text(channel.name)
                    .font(.headline)
                    .padding(.horizontal)
            } else {
                EmptyStateView(
                    title: "Nothing Playing",
                    systemImage: "play.slash",
                    message: "Select a channel from the Channels tab."
                )
            }

            Spacer()

            PlayerControlsView(player: player)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

/// Bridges AVPlayer to SwiftUI on iOS via AVPlayerViewController.
private struct IOSVideoPlayer: UIViewControllerRepresentable {
    let avPlayer: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = avPlayer
        vc.allowsPictureInPicturePlayback = true
        vc.showsPlaybackControls = false // We use PlayerControlsView instead
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== avPlayer {
            uiViewController.player = avPlayer
        }
    }
}
#endif
