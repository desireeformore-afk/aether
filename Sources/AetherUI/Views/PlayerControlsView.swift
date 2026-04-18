import SwiftUI
import AetherCore

/// Transport controls: play/pause, prev, next, mute, volume.
/// Shared across macOS, iOS, tvOS — layout adapts via environment.
public struct PlayerControlsView: View {
    @Bindable public var player: PlayerCore

    public init(player: PlayerCore) { self.player = player }

    private var isPlaying: Bool { player.state == .playing }

    public var body: some View {
        HStack(spacing: 20) {
            Button { player.playPrevious() } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous channel")

            Button { player.togglePlayPause() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button { player.playNext() } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next channel")

            Spacer()

            Button { player.toggleMute() } label: {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isMuted ? "Unmute" : "Mute")

            #if !os(tvOS)
            Slider(value: Binding(
                get: { Double(player.volume) },
                set: { player.setVolume(Float($0)) }
            ), in: 0...1)
            .frame(width: 80)
            .accessibilityLabel("Volume")
            #endif
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
