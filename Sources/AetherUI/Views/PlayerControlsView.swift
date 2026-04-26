import SwiftUI
import AetherCore

/// Transport controls: play/pause, prev, next, mute, volume, seek.
/// All platforms — layout adapts via environment.
public struct PlayerControlsView: View {
    @Bindable public var player: PlayerCore
    @Binding public var showStats: Bool
    @State private var showTrackPicker = false
    @FocusState private var isFocused: Bool

    public init(player: PlayerCore, showStats: Binding<Bool>) {
        self.player = player
        self._showStats = showStats
    }

    private var isPlaying: Bool { player.state == .playing }
    private var isVOD: Bool { !player.isLiveStream }

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
                    Text(cleanPlayerTitle(channel.name))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260, alignment: .leading)
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
                        VLCTrackPickerView(player: player)
                    }
                }
                #endif
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.space) {
            player.togglePlayPause()
            return .handled
        }
        .onKeyPress(.escape) {
            player.stop()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if player.isLiveStream { player.playPrevious() } else { player.seek(by: -10) }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if player.isLiveStream { player.playNext() } else { player.seek(by: 10) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            player.adjustVolume(delta: 0.1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            player.adjustVolume(delta: -0.1)
            return .handled
        }
        .onKeyPress(KeyEquivalent("m")) {
            player.toggleMute()
            return .handled
        }
        .onKeyPress(KeyEquivalent("f")) {
            #if os(macOS)
            NSApp.mainWindow?.toggleFullScreen(nil)
            #endif
            return .handled
        }
    }
}

// MARK: - Helpers

private func cleanPlayerTitle(_ name: String) -> String {
    let prefixes = [
        "AMZ - ", "AMZ-", "NF - ", "NF-", "NETFLIX - ", "Netflix - ",
        "Netflix 4K Premium - ", "Netflix 4K - ", "4K-A+ - ", "4K+ - ",
        "4K - ", "HD - ", "FHD - ", "UHD - ", "DSNP - ", "HMAX - ",
        "ATVP - ", "PCOK - ", "HULU - ", "STAN - ",
    ]
    var result = name
    for prefix in prefixes {
        if result.uppercased().hasPrefix(prefix.uppercased()) {
            result = String(result.dropFirst(prefix.count))
            break
        }
    }
    return result.trimmingCharacters(in: .whitespaces)
}

// MARK: - VLCTrackPickerView

struct VLCTrackPickerView: View {
    @Bindable var player: PlayerCore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !player.availableAudioTracks.isEmpty {
                Text("Audio")
                    .font(.headline)
                    .padding(.bottom, 2)
                ForEach(player.availableAudioTracks) { track in
                    Button {
                        player.selectAudioTrack(track)
                    } label: {
                        HStack {
                            Text(track.displayName)
                            Spacer()
                            if player.selectedAudioTrackID == track.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !player.availableSubtitleTracks.isEmpty {
                if !player.availableAudioTracks.isEmpty { Divider() }
                Text("Subtitles")
                    .font(.headline)
                    .padding(.bottom, 2)
                Button {
                    player.selectSubtitleTrack(nil)
                } label: {
                    HStack {
                        Text("Off")
                        Spacer()
                        if player.selectedSubtitleTrackID == -1 {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                ForEach(player.availableSubtitleTracks) { track in
                    Button {
                        player.selectSubtitleTrack(track)
                    } label: {
                        HStack {
                            Text(track.displayName)
                            Spacer()
                            if player.selectedSubtitleTrackID == track.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if player.availableAudioTracks.isEmpty && player.availableSubtitleTracks.isEmpty {
                Text("No tracks available")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}
