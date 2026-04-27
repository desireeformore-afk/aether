import SwiftUI
import AetherCore

/// Micro-animation style for premium button feedback
public struct HoverScaleButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Transport controls: play/pause, prev, next, mute, volume, seek.
/// All platforms — layout adapts via environment.
public struct PlayerControlsView: View {
    @Bindable public var player: PlayerCore
    @Binding public var showStats: Bool
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
                        .font(.title3)
                }
                .buttonStyle(HoverScaleButtonStyle())
                .accessibilityLabel("Previous channel")

                if isVOD {
                    Button { player.seek(by: -10) } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(HoverScaleButtonStyle())
                    .accessibilityLabel("Skip back 10 seconds")
                }

                Button { player.togglePlayPause() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(HoverScaleButtonStyle())
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                if isVOD {
                    Button { player.seek(by: 10) } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(HoverScaleButtonStyle())
                    .accessibilityLabel("Skip forward 10 seconds")
                }

                Button { player.playNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(HoverScaleButtonStyle())
                .accessibilityLabel("Next channel")

                if let channel = player.currentChannel {
                    Text(VODNormalizer.extractTagsAndClean(channel.name).cleanTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }

                Spacer()

                Button { player.toggleMute() } label: {
                    Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(HoverScaleButtonStyle())
                .accessibilityLabel(player.isMuted ? "Unmute" : "Mute")

                #if !os(tvOS)
                Slider(value: Binding(
                    get: { Double(player.volume) },
                    set: { player.setVolume(Float($0)) }
                ), in: 0...1)
                .frame(width: 80)
                .accessibilityLabel("Volume")
                
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button {
                            player.setPlaybackRate(Float(rate))
                        } label: {
                            HStack {
                                Text("\(String(format: "%g", rate))x")
                                if player.playbackRate == Float(rate) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "gauge.medium")
                        .font(.title3)
                }
                .buttonStyle(HoverScaleButtonStyle())
                .accessibilityLabel("Playback Speed")
                #endif

                #if !os(tvOS)
                if let channel = player.currentChannel {
                    Menu {
                        // VIRTUAL STREAM VARIANTS
                        if !channel.availableVariants.isEmpty, !player.isLiveStream {
                            Text("Wersje Zdalne (Język / Jakość)")
                            ForEach(channel.availableVariants) { variant in
                                Button {
                                    player.hotSwapVariant(to: variant)
                                } label: {
                                    if channel.streamURL == variant.streamURL {
                                        Label(variant.name + " (Aktywny)", systemImage: "checkmark")
                                    } else {
                                        Text(variant.name)
                                    }
                                }
                            }
                            Divider()
                        }

                        // LOCAL EMBEDDED TRACKS
                        if !player.availableAudioTracks.isEmpty {
                            Text("Audio (Natywne VLC)") // Label for section
                            ForEach(player.availableAudioTracks) { track in
                                Button {
                                    player.selectAudioTrack(track)
                                } label: {
                                    if player.selectedAudioTrackID == track.id {
                                        Label(track.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(track.displayName)
                                    }
                                }
                            }
                            Divider()
                        }
                        
                        if !player.availableSubtitleTracks.isEmpty {
                            Text("Subtitles")
                            Button {
                                player.selectSubtitleTrack(nil)
                            } label: {
                                if player.selectedSubtitleTrackID == -1 {
                                    Label("Off", systemImage: "checkmark")
                                } else {
                                    Text("Off")
                                }
                            }
                            ForEach(player.availableSubtitleTracks) { track in
                                Button {
                                    player.selectSubtitleTrack(track)
                                } label: {
                                    if player.selectedSubtitleTrackID == track.id {
                                        Label(track.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(track.displayName)
                                    }
                                }
                            }
                        }
                        if player.availableAudioTracks.isEmpty && player.availableSubtitleTracks.isEmpty {
                            Text("No tracks available")
                        }
                    } label: {
                        Image(systemName: "captions.bubble")
                            .font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .buttonStyle(HoverScaleButtonStyle())
                    .accessibilityLabel("Audio and Subtitles")
                }
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 40)
        .padding(.bottom, 24)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .focusable()
        #if os(macOS)
        .focusEffectDisabled(true)
        #endif
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

