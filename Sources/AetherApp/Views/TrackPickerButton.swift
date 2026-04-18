import SwiftUI
import AetherCore

/// Button to open track picker for audio and subtitles.
struct TrackPickerButton: View {
    @ObservedObject var trackService: TrackService
    @ObservedObject var player: PlayerCore
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
        .sheet(isPresented: $showTrackPicker) {
            TrackPickerView(trackService: trackService, playerItem: player.player.currentItem)
        }
    }

    private var hasMultipleTracks: Bool {
        trackService.audioTracks.count > 1 || !trackService.subtitleTracks.isEmpty
    }
}
