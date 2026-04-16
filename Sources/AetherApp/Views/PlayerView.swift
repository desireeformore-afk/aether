import SwiftUI
import AVKit
import AetherCore

/// Detail pane: AVPlayer video + transport controls.
struct PlayerView: View {
    @ObservedObject var player: PlayerCore

    var body: some View {
        ZStack {
            Color.aetherBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Video layer
                VideoPlayerLayer(avPlayer: player.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .overlay(alignment: .bottomLeading) {
                        stateOverlay
                            .padding()
                    }

                // Controls
                PlayerControls(player: player)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch player.state {
        case .loading:
            ProgressView()
                .scaleEffect(1.5)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.aetherCaption)
                .foregroundStyle(.white)
                .padding(8)
                .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        default:
            EmptyView()
        }
    }
}

/// Wraps `AVPlayer` in an `NSView` for SwiftUI via `NSViewRepresentable`.
struct VideoPlayerLayer: NSViewRepresentable {
    let avPlayer: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = avPlayer
        view.controlsStyle = .none
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== avPlayer {
            nsView.player = avPlayer
        }
    }
}

/// Transport controls bar.
struct PlayerControls: View {
    @ObservedObject var player: PlayerCore

    var body: some View {
        HStack(spacing: 20) {
            // Channel info
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentChannel?.name ?? "No channel selected")
                    .font(.aetherBody)
                    .foregroundStyle(Color.aetherText)
                    .lineLimit(1)
                if let group = player.currentChannel?.groupTitle, !group.isEmpty {
                    Text(group)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            // Play / Pause
            Button(action: togglePlayPause) {
                Image(systemName: playPauseIcon)
                    .font(.title2)
                    .foregroundStyle(Color.aetherPrimary)
            }
            .buttonStyle(.plain)
            .disabled(player.currentChannel == nil)
            .help(isPlaying ? "Pause" : "Play")

            // Stop
            Button(action: { player.stop() }) {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .foregroundStyle(player.currentChannel == nil ? .secondary : Color.aetherText)
            }
            .buttonStyle(.plain)
            .disabled(player.currentChannel == nil)
            .help("Stop")

            Divider().frame(height: 24)

            // Mute
            Button(action: { player.toggleMute() }) {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(Color.aetherText)
            }
            .buttonStyle(.plain)
            .help(player.isMuted ? "Unmute" : "Mute")

            // Volume slider
            Slider(value: Binding(
                get: { Double(player.volume) },
                set: { player.setVolume(Float($0)) }
            ), in: 0...1)
            .frame(width: 80)
            .disabled(player.isMuted)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var isPlaying: Bool { player.state == .playing }

    private var playPauseIcon: String {
        isPlaying ? "pause.fill" : "play.fill"
    }

    private func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.resume()
        }
    }
}
