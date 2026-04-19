@preconcurrency import AVFoundation

/// Applies IPTV-optimised buffering and network settings to AVPlayer/AVPlayerItem.
public enum BufferingConfig {

    /// Forward buffer for live streams — 10s is enough, keeps latency low.
    public static let preferredForwardBufferDuration: TimeInterval = 10

    public static func apply(to item: AVPlayerItem) {
        // 4s forward buffer — enough for keyframe arrival before playback starts
        item.preferredForwardBufferDuration = 4
        item.preferredPeakBitRate = 0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
    }

    public static func apply(to player: AVPlayer) {
        // false = start immediately without infinite wait
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback = false
    }
}
