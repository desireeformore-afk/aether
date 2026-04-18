import Foundation
import SwiftData

/// SwiftData record for tracking watch progress on movies and series episodes.
@Model
public final class WatchProgressRecord {
    /// Unique identifier for this progress record.
    public var id: UUID

    /// ID of the content (movie ID or episode ID).
    public var contentID: UUID

    /// Type of content: "movie" or "episode".
    public var contentType: String

    /// Stream URL string.
    public var streamURLString: String

    /// Last watched position in seconds.
    public var lastPosition: TimeInterval

    /// Total duration in seconds (if known).
    public var duration: TimeInterval?

    /// Completion percentage (0.0 to 1.0).
    public var completionPercent: Double

    /// Whether this content has been fully watched.
    public var isCompleted: Bool

    /// Last watched timestamp.
    public var lastWatchedAt: Date

    /// For episodes: series name.
    public var seriesName: String?

    /// For episodes: season number.
    public var season: Int?

    /// For episodes: episode number.
    public var episode: Int?

    /// For movies: title.
    public var movieTitle: String?

    public init(
        id: UUID = UUID(),
        contentID: UUID,
        contentType: String,
        streamURLString: String,
        lastPosition: TimeInterval = 0,
        duration: TimeInterval? = nil,
        completionPercent: Double = 0,
        isCompleted: Bool = false,
        lastWatchedAt: Date = .now,
        seriesName: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        movieTitle: String? = nil
    ) {
        self.id = id
        self.contentID = contentID
        self.contentType = contentType
        self.streamURLString = streamURLString
        self.lastPosition = lastPosition
        self.duration = duration
        self.completionPercent = completionPercent
        self.isCompleted = isCompleted
        self.lastWatchedAt = lastWatchedAt
        self.seriesName = seriesName
        self.season = season
        self.episode = episode
        self.movieTitle = movieTitle
    }
}
