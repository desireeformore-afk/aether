import Foundation
@preconcurrency import AVFoundation

/// Represents a selectable HLS quality variant.
public struct StreamQuality: Identifiable, Sendable, Hashable {
    public let id: String
    public let label: String
    /// Approximate peak bitrate in bits-per-second (0 = auto/best).
    public let peakBitRate: Double

    public static let auto = StreamQuality(id: "auto", label: "Auto", peakBitRate: 0)

    public init(id: String, label: String, peakBitRate: Double) {
        self.id = id
        self.label = label
        self.peakBitRate = peakBitRate
    }
}

/// Standard quality presets for HLS streams.
public enum StreamQualityPreset: String, CaseIterable, Sendable {
    case auto   = "Auto"
    case high   = "High (4 Mbps)"
    case medium = "Medium (1.5 Mbps)"
    case low    = "Low (500 kbps)"

    public var quality: StreamQuality {
        switch self {
        case .auto:   return StreamQuality(id: "auto",   label: "Auto",            peakBitRate: 0)
        case .high:   return StreamQuality(id: "high",   label: "High (4 Mbps)",   peakBitRate: 4_000_000)
        case .medium: return StreamQuality(id: "medium", label: "Medium (1.5 Mbps)", peakBitRate: 1_500_000)
        case .low:    return StreamQuality(id: "low",    label: "Low (500 kbps)",   peakBitRate: 500_000)
        }
    }
}

/// Applies quality constraints to an `AVPlayer`'s current item.
public struct StreamQualityService: Sendable {
    public init() {}

    /// Applies the given quality to the player's current `AVPlayerItem`.
    /// For HLS streams, sets `preferredPeakBitRate`; 0 = no limit (auto).
    public func apply(_ quality: StreamQuality, to player: AVPlayer) {
        player.currentItem?.preferredPeakBitRate = quality.peakBitRate
    }
}
