import SwiftUI
@preconcurrency import AVFoundation
import CoreMedia
import AetherCore

struct StreamStatsView: View {
    let player: AVPlayer
    @State private var stats = StreamStats()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            statRow("Resolution", value: stats.resolutionLabel)
            statRow("Codec",      value: stats.codec)
            statRow("Bitrate",    value: stats.bitrateKbps.map { "\($0) kbps" } ?? "—")
            statRow("Buffer",     value: stats.bufferingPercent.map { "\($0)%" } ?? "—")
            statRow("Dropped",    value: "\(stats.droppedFrames) frames")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            stats = StreamStats(player: player)
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

struct StreamStats {
    let bitrateKbps: Int?
    let droppedFrames: Int
    let bufferSeconds: Double?
    let presentationSize: CGSize?
    let codec: String

    var resolutionLabel: String {
        guard let size = presentationSize, size.width > 0 else { return "—" }
        return "\(Int(size.width))×\(Int(size.height))"
    }

    var bufferingPercent: Int? {
        guard let sec = bufferSeconds else { return nil }
        return min(100, Int(sec / 10.0 * 100))
    }

    init() {
        bitrateKbps = nil
        droppedFrames = 0
        bufferSeconds = nil
        presentationSize = nil
        codec = "—"
    }

    init(player: AVPlayer) {
        // Indicated bitrate from HLS access log
        if let log = player.currentItem?.accessLog(),
           let event = log.events.last {
            bitrateKbps = event.indicatedBitrate > 0
                ? Int(event.indicatedBitrate / 1000) : nil
        } else {
            bitrateKbps = nil
        }

        // Dropped video frames
        droppedFrames = Int(player.currentItem?
            .accessLog()?.events.last?.numberOfDroppedVideoFrames ?? 0)

        // Loaded time ranges → buffer ahead
        if let item = player.currentItem,
           let range = item.loadedTimeRanges.first?.timeRangeValue {
            let current = item.currentTime().seconds
            let end = (range.start + range.duration).seconds
            bufferSeconds = max(0, end - current)
        } else {
            bufferSeconds = nil
        }

        // Presentation size (video resolution)
        presentationSize = player.currentItem?.presentationSize

        // Codec: read from video track format description
        codec = StreamStats.resolveCodec(from: player)
    }

    private static func resolveCodec(from player: AVPlayer) -> String {
        guard let item = player.currentItem else { return "—" }
        let videoTrack = item.tracks.first { $0.assetTrack?.mediaType == .video }
        guard let assetTrack = videoTrack?.assetTrack,
              let descAny = assetTrack.formatDescriptions.first,
              let desc = descAny as? CMFormatDescription else { return "—" }
        let subType = CMFormatDescriptionGetMediaSubType(desc)
        let bytes: [UInt8] = [
            UInt8((subType >> 24) & 0xFF),
            UInt8((subType >> 16) & 0xFF),
            UInt8((subType >> 8)  & 0xFF),
            UInt8( subType        & 0xFF)
        ]
        let tag = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? "—"
        return tag.isEmpty ? "—" : tag
    }
}
