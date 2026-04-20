import Foundation
import SwiftData

/// Lightweight SwiftData record for a watch history entry.
@Model
public final class WatchHistoryRecord {
    public var id: UUID
    public var channelID: UUID
    public var channelName: String
    public var streamURLString: String
    public var logoURLString: String?
    public var groupTitle: String
    public var epgId: String?
    public var watchedAt: Date
    public var durationSeconds: Int

    // Progress tracking (for "Continue Watching")
    public var watchedSecondsDouble: Double
    public var totalDurationSeconds: Double
    public var contentType: String  // "live", "movie", "series"

    public var progressFraction: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return min(watchedSecondsDouble / totalDurationSeconds, 1.0)
    }

    public var isFinished: Bool { progressFraction > 0.9 }

    /// True when >5% and <90% watched — eligible for "Continue Watching"
    public var isContinueWatching: Bool {
        progressFraction > 0.05 && progressFraction < 0.9
    }

    public init(channel: Channel, watchedAt: Date = .now, durationSeconds: Int = 0) {
        self.id = UUID()
        self.channelID = channel.id
        self.channelName = channel.name
        self.streamURLString = channel.streamURL.absoluteString
        self.logoURLString = channel.logoURL?.absoluteString
        self.groupTitle = channel.groupTitle
        self.epgId = channel.epgId
        self.watchedAt = watchedAt
        self.durationSeconds = durationSeconds
        self.watchedSecondsDouble = 0
        self.totalDurationSeconds = 0
        self.contentType = channel.contentType == .movie ? "movie"
            : channel.contentType == .series ? "series"
            : "live"
    }

    public func toChannel() -> Channel? {
        guard let url = URL(string: streamURLString) else { return nil }
        return Channel(
            id: channelID,
            name: channelName,
            streamURL: url,
            logoURL: logoURLString.flatMap { URL(string: $0) },
            groupTitle: groupTitle,
            epgId: epgId
        )
    }
}
