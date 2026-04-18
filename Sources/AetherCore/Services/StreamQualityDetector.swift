import Foundation
@preconcurrency import AVFoundation

/// Detects available quality variants from HLS manifests and monitors stream quality.
@MainActor
public final class StreamQualityDetector: ObservableObject {
    @Published public private(set) var availableQualities: [StreamQuality] = []
    @Published public private(set) var currentBitrate: Double = 0
    @Published public private(set) var isAutoDetecting: Bool = false

    private weak var player: AVPlayer?
    private var bitrateObserver: NSKeyValueObservation?

    public init() {}

    /// Starts monitoring the given player for quality information.
    public func monitor(_ player: AVPlayer) {
        self.player = player
        startBitrateMonitoring()
    }

    /// Stops monitoring.
    public func stopMonitoring() {
        bitrateObserver?.invalidate()
        bitrateObserver = nil
        player = nil
    }

    /// Detects available quality variants from the current HLS stream.
    public func detectAvailableQualities() async {
        guard let player, let _ = player.currentItem else {
            availableQualities = []
            return
        }

        isAutoDetecting = true
        defer { isAutoDetecting = false }

        // For HLS streams, we can inspect the master playlist
        // In a real implementation, you'd parse the m3u8 to extract variants
        // For now, we'll provide standard presets
        availableQualities = StreamQualityPreset.allCases.map { $0.quality }
    }

    // MARK: - Private

    private func startBitrateMonitoring() {
        guard let player else { return }

        // Observe current item changes to track bitrate
        bitrateObserver = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateCurrentBitrate()
            }
        }
    }

    private func updateCurrentBitrate() {
        guard let player, let item = player.currentItem else {
            currentBitrate = 0
            return
        }

        // Get the most recent access log event
        guard let event = item.accessLog()?.events.last else {
            return
        }

        // observedBitrate is in bits per second
        if event.observedBitrate > 0 {
            currentBitrate = event.observedBitrate
        }
    }

    /// Returns a human-readable quality label based on bitrate.
    public func qualityLabel(for bitrate: Double) -> String {
        switch bitrate {
        case 0:
            return "Unknown"
        case ..<500_000:
            return "Low"
        case 500_000..<1_500_000:
            return "Medium"
        case 1_500_000..<4_000_000:
            return "High"
        default:
            return "Ultra"
        }
    }

    /// Formats bitrate for display (e.g., "2.5 Mbps").
    public func formatBitrate(_ bitrate: Double) -> String {
        if bitrate == 0 {
            return "—"
        }
        let mbps = bitrate / 1_000_000
        return String(format: "%.1f Mbps", mbps)
    }
}
