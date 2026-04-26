import SwiftUI
import VLCKit
import AetherCore

/// HUD overlay showing live stream statistics from VLC's built-in stats engine.
/// VLC provides richer, more accurate stats than AVPlayer's accessLog:
/// - Decoded/displayed/lost frames (from GPU decoder)
/// - Demux bitrate (actual bytes from network, not HLS manifest estimate)
/// - Input bitrate (raw transport layer)
struct StreamStatsView: View {
    let player: PlayerCore
    @State private var decoded: Int = 0
    @State private var displayed: Int = 0
    @State private var lost: Int = 0
    @State private var demuxBitrate: Float = 0
    @State private var inputBitrate: Float = 0
    @State private var codec: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            statRow("Codec",       value: codec)
            statRow("Net In",      value: inputBitrate > 0 ? String(format: "%.0f kbps", inputBitrate * 8) : "—")
            statRow("Demux",       value: demuxBitrate > 0 ? String(format: "%.0f kbps", demuxBitrate * 8) : "—")
            statRow("Decoded",     value: "\(decoded) frames")
            statRow("Displayed",   value: "\(displayed) frames")
            statRow("Dropped",     value: "\(lost) frames")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshStats()
        }
        .onAppear { refreshStats() }
    }

    private func refreshStats() {
        guard let vlc = player.vlcPlayerInternal else { return }

        // VLC stats: cumulative frame counts since playback started
        if let media = vlc.media {
            let stats = media.statistics  // VLCMedia.Stats is non-optional in VLCKit 4
            decoded      = Int(stats.decodedVideo)
            displayed    = Int(stats.displayedPictures)
            lost         = Int(stats.lostPictures)
            demuxBitrate = stats.demuxBitrate
            inputBitrate = stats.inputBitrate
        }

        // VLCKit 4: codec name via instance method on VLCMediaTrack (returns non-optional String)
        if let videoTrack = vlc.videoTracks.first {
            let name = videoTrack.codecName()
            codec = name.isEmpty ? "—" : name
        } else if let audioTrack = vlc.audioTracks.first {
            let name = audioTrack.codecName()
            codec = name.isEmpty ? "—" : name
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
        }
    }
}
