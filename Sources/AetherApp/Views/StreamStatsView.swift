import SwiftUI
import AVFoundation
import AetherCore

struct StreamStatsView: View {
    let player: AVPlayer
    @State private var stats = StreamStats()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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
