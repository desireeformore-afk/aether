import SwiftUI
import AetherCore

/// Transport controls: play/pause, prev, next, mute, volume.
/// Shared across macOS, iOS, tvOS — layout adapts via environment.
public struct PlayerControlsView: View {
    @Bindable public var player: PlayerCore
    @Binding public var showStats: Bool

    public init(player: PlayerCore, showStats: Binding<Bool>) { 
        self.player = player 
        self._showStats = showStats
    }

    private var isPlaying: Bool { player.state == .playing }

    private var isVOD: Bool {
        player.currentChannel.map { $0.contentType != .liveTV } ?? false
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isVOD {
                SeekBarView(player: player)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            HStack(spacing: 20) {
                Button { player.playPrevious() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous channel")

                if isVOD {
                    Button { player.seek(by: -10) } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip back 10 seconds")
                }

                Button { player.togglePlayPause() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                if isVOD {
                    Button { player.seek(by: 10) } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip forward 10 seconds")
                }

                Button { player.playNext() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next channel")

                if let channel = player.currentChannel {
                    Text(channel.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

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
        }
        .background(.ultraThinMaterial)
    }
}
