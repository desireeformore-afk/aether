import SwiftUI
import AetherCore

/// Button to open track picker for audio and subtitles.
struct TrackPickerButton: View {
    @State var trackService: TrackService
    @Bindable var player: PlayerCore
    @State private var showTrackPicker = false

    var body: some View {
        Button(action: {
            showTrackPicker = true
        }) {
            Image(systemName: hasMultipleTracks ? "waveform.badge.magnifyingglass" : "waveform")
                .font(.title3)
                .foregroundStyle(hasMultipleTracks ? Color.aetherAccent : Color.aetherText)
        }
        .buttonStyle(.plain)
        .help("Audio & Subtitle Tracks")
        .popover(isPresented: $showTrackPicker, arrowEdge: .top) {
            TrackPickerPopoverContent(player: player)
        }
    }

    private var hasMultipleTracks: Bool {
        player.availableAudioTracks.count > 1 || !player.availableSubtitleTracks.isEmpty
    }
}

// MARK: - TrackPickerPopoverContent

private struct TrackPickerPopoverContent: View {
    @Bindable var player: PlayerCore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !player.availableAudioTracks.isEmpty {
                Text("Audio")
                    .font(.headline)
                ForEach(player.availableAudioTracks) { track in
                    Button {
                        player.selectAudioTrack(track)
                    } label: {
                        HStack {
                            Text(track.displayName)
                            Spacer()
                            if player.selectedAudioTrackID == track.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if !player.availableSubtitleTracks.isEmpty {
                if !player.availableAudioTracks.isEmpty { Divider() }
                Text("Subtitles").font(.headline)
                Button {
                    player.selectSubtitleTrack(nil)
                } label: {
                    HStack {
                        Text("Off")
                        Spacer()
                        if player.selectedSubtitleTrackID == -1 {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
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
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if player.availableAudioTracks.isEmpty && player.availableSubtitleTracks.isEmpty {
                Text("No tracks available").foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 180)
    }
}
