@preconcurrency import AVFoundation

/// Applies IPTV-optimised buffering and network settings to AVPlayer/AVPlayerItem.
public enum BufferingConfig {

    /// Buffer for good-signal streams: small = low latency.
    public static let normalForwardBuffer: TimeInterval = 4
    /// Buffer for weak-signal streams: larger = fewer stalls.
    public static let adaptiveForwardBuffer: TimeInterval = 16

    public static func apply(to item: AVPlayerItem) {
        item.preferredForwardBufferDuration = normalForwardBuffer
        item.preferredPeakBitRate = 0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
    }

    /// Increases forward buffer for weak-signal recovery.
    public static func applyAdaptive(to item: AVPlayerItem) {
        item.preferredForwardBufferDuration = adaptiveForwardBuffer
    }

    /// Resets to normal buffer after signal recovers.
    public static func resetToNormal(for item: AVPlayerItem) {
        item.preferredForwardBufferDuration = normalForwardBuffer
    }

    public static func apply(to player: AVPlayer) {
        // false = start immediately without infinite wait
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
    }
}
