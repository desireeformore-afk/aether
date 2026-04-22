import SwiftUI
@preconcurrency import AVFoundation
import AetherCore

/// Transport controls: play/pause, prev, next, mute, volume.
/// Shared across macOS, iOS, tvOS — layout adapts via environment.
public struct PlayerControlsView: View {
    @Bindable public var player: PlayerCore
    @Binding public var showStats: Bool
    @State private var showTrackPicker = false

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

                #if os(macOS)
                Button {
                    player.startPiP()
                } label: {
                    Image(systemName: "pip.enter")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Picture in Picture")
                .disabled(player.currentChannel == nil)
                #endif

                #if !os(tvOS)
                if player.currentChannel != nil {
                    Button {
                        showTrackPicker.toggle()
                    } label: {
                        Image(systemName: "captions.bubble")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Audio and Subtitles")
                    .popover(isPresented: $showTrackPicker, arrowEdge: .top) {
                        TrackPickerView(player: player)
                    }
                }
                #endif
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .onKeyPress(.space) {
            player.togglePlayPause()
            return .handled
        }
        .onKeyPress(.escape) {
            player.stop()
            return .handled
        }
    }
}

// MARK: - TrackPickerView

struct TrackPickerView: View {
    @Bindable var player: PlayerCore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !player.availableAudioOptions.isEmpty {
                Text("Audio")
                    .font(.headline)
                    .padding(.bottom, 2)
                ForEach(player.availableAudioOptions, id: \.self) { option in
                    Button {
                        player.selectAudioOption(option)
                    } label: {
                        HStack {
                            Text(option.displayName)
                            Spacer()
                            if option == player.selectedAudioOption {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !player.availableSubtitleOptions.isEmpty {
                if !player.availableAudioOptions.isEmpty { Divider() }
                Text("Subtitles")
                    .font(.headline)
                    .padding(.bottom, 2)
                Button {
                    player.selectSubtitleOption(nil)
                } label: {
                    HStack {
                        Text("Off")
                        Spacer()
                        if player.selectedSubtitleOption == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                ForEach(player.availableSubtitleOptions, id: \.self) { option in
                    Button {
                        player.selectSubtitleOption(option)
                    } label: {
                        HStack {
                            Text(option.displayName)
                            Spacer()
                            if option == player.selectedSubtitleOption {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if player.availableAudioOptions.isEmpty && player.availableSubtitleOptions.isEmpty {
                Text("No tracks available")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}
