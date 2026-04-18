import SwiftUI
@preconcurrency import AVFoundation
import AetherCore

struct StreamStatsView: View {
    let player: AVPlayer
    @State private var stats = StreamStats()
    @State private var qualityLabel: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            statRow("Quality", value: qualityLabel)
            statRow("Bitrate", value: stats.bitrateKbps.map { "\($0) kbps" } ?? "—")
            statRow("Dropped", value: "\(stats.droppedFrames) frames")
            statRow("Buffer",  value: stats.bufferSeconds.map { String(format: "%.1fs", $0) } ?? "—")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            stats = StreamStats(player: player)
            updateQualityLabel()
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
        }
    }

    private func updateQualityLabel() {
        guard let bitrate = stats.bitrateKbps else {
            qualityLabel = "—"
            return
        }

        let bps = Double(bitrate) * 1000
        switch bps {
        case ..<500_000:
            qualityLabel = "Low"
        case 500_000..<1_500_000:
            qualityLabel = "Medium"
        case 1_500_000..<4_000_000:
            qualityLabel = "High"
        default:
            qualityLabel = "Ultra"
        }
    }
}

struct StreamStats {
    let bitrateKbps: Int?
    let droppedFrames: Int
    let bufferSeconds: Double?

    init() { bitrateKbps = nil; droppedFrames = 0; bufferSeconds = nil }

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
    }
}
