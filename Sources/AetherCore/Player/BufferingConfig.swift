import AVFoundation

/// Applies aggressive buffering settings to an `AVPlayerItem` / `AVPlayer`.
public enum BufferingConfig {

    /// Preferred forward buffer duration in seconds — 30s (default is ~50KB for HLS).
    public static let preferredForwardBufferDuration: TimeInterval = 30

    /// Apply buffering settings to an `AVPlayerItem`.
    public static func apply(to item: AVPlayerItem) {
        item.preferredForwardBufferDuration = preferredForwardBufferDuration
    }

    /// Apply buffering settings to an `AVPlayer`.
    /// `automaticallyWaitsToMinimizeStalling = false` → start immediately,
    /// don't wait for an optimal buffer level.
    public static func apply(to player: AVPlayer) {
        player.automaticallyWaitsToMinimizeStalling = false
    }
}
