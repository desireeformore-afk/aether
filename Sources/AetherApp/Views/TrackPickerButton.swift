     1|import SwiftUI
     2|import AetherCore
     3|
     4|/// Button to open track picker for audio and subtitles.
     5|struct TrackPickerButton: View {
     6|    @ObservedObject var trackService: TrackService
     7|    @Bindable var player: PlayerCore
     8|    @State private var showTrackPicker = false
     9|
    10|    var body: some View {
    11|        Button(action: {
    12|            showTrackPicker = true
    13|        }) {
    14|            Image(systemName: hasMultipleTracks ? "waveform.badge.magnifyingglass" : "waveform")
    15|                .font(.title3)
    16|                .foregroundStyle(hasMultipleTracks ? Color.aetherAccent : Color.aetherText)
    17|        }
    18|        .buttonStyle(.plain)
    19|        .help("Audio & Subtitle Tracks")
    20|        .sheet(isPresented: $showTrackPicker) {
    21|            TrackPickerView(trackService: trackService, playerItem: player.player.currentItem)
    22|        }
    23|    }
    24|
    25|    private var hasMultipleTracks: Bool {
    26|        trackService.audioTracks.count > 1 || !trackService.subtitleTracks.isEmpty
    27|    }
    28|}
    29|