     1|import SwiftUI
     2|import AVKit
     3|import AetherCore
     4|import AetherUI
     5|
     6|#if os(iOS)
     7|/// Player view for iOS — uses AVPlayerViewController for native controls and PiP.
     8|struct IOSPlayerView: View {
     9|    @Bindable var player: PlayerCore
    10|
    11|    var body: some View {
    12|        VStack(spacing: 0) {
    13|            IOSVideoPlayer(avPlayer: player.player)
    14|                .aspectRatio(16 / 9, contentMode: .fit)
    15|                .clipShape(RoundedRectangle(cornerRadius: 8))
    16|                .padding()
    17|
    18|            if let channel = player.currentChannel {
    19|                Text(channel.name)
    20|                    .font(.headline)
    21|                    .padding(.horizontal)
    22|            } else {
    23|                EmptyStateView(
    24|                    title: "Nothing Playing",
    25|                    systemImage: "play.slash",
    26|                    message: "Select a channel from the Channels tab."
    27|                )
    28|            }
    29|
    30|            Spacer()
    31|
    32|            PlayerControlsView(player: player)
    33|        }
    34|        .background(Color(uiColor: .systemBackground))
    35|    }
    36|}
    37|
    38|/// Bridges AVPlayer to SwiftUI on iOS via AVPlayerViewController.
    39|private struct IOSVideoPlayer: UIViewControllerRepresentable {
    40|    let avPlayer: AVPlayer
    41|
    42|    func makeUIViewController(context: Context) -> AVPlayerViewController {
    43|        let vc = AVPlayerViewController()
    44|        vc.player = avPlayer
    45|        vc.allowsPictureInPicturePlayback = true
    46|        vc.showsPlaybackControls = false // We use PlayerControlsView instead
    47|        return vc
    48|    }
    49|
    50|    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
    51|        if uiViewController.player !== avPlayer {
    52|            uiViewController.player = avPlayer
    53|        }
    54|    }
    55|}
    56|#endif
    57|