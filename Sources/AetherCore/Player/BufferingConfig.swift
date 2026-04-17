import AVFoundation

/// Applies aggressive buffering settings to an `AVPlayerItem`.
public enum BufferingConfig {

    /// Preferred forward buffer duration in seconds — 30s (default is ~50KB/5s for HLS).
    public static let preferredForwardBufferDuration: TimeInterval = 30

    public static func apply(to item: AVPlayerItem) {
        item.preferredForwardBufferDuration = preferredForwardBufferDuration
    }

    public static func apply(to player: AVPlayer) {
        // False = start immediately, don't wait for optimal buffer
        player.automaticallyWaitsToMinimizeStalling = false
    }
}
