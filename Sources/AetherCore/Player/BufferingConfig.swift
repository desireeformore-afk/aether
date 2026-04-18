import AVFoundation

/// Applies IPTV-optimised buffering and network settings to AVPlayer/AVPlayerItem.
public enum BufferingConfig {

    /// Forward buffer for live streams — 10s is enough, keeps latency low.
    public static let preferredForwardBufferDuration: TimeInterval = 10

    public static func apply(to item: AVPlayerItem) {
        item.preferredForwardBufferDuration = preferredForwardBufferDuration
        // Disable automatic bitrate switching — we control quality manually
        item.preferredPeakBitRate = 0 // 0 = unlimited, set per-quality elsewhere
        // Allow network stalls to be retried by the system before we get notified
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        #if os(iOS) || os(tvOS)
        item.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithm.lowQualityZeroLatency
        #else
        item.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithm.timePitch
        #endif
    }

    public static func apply(to player: AVPlayer) {
        // Wait for buffer — prevents QUIC-related stutter on IPTV streams
        player.automaticallyWaitsToMinimizeStalling = true
        // Don't apply external playback restrictions
        player.allowsExternalPlayback = false
    }
}
