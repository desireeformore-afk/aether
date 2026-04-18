import Foundation
import SwiftData

/// SwiftData record for storing movie metadata and preferences.
@Model
public final class MovieRecord {
    /// Unique identifier for the movie.
    public var id: UUID

    /// Title of the movie.
    public var title: String

    /// Release year (if available).
    public var year: Int?

    /// Genre (if available).
    public var genre: String?

    /// Duration in seconds (if available).
    public var duration: TimeInterval?

    /// Stream URL string.
    public var streamURLString: String

    /// Optional poster URL string.
    public var posterURLString: String?

    /// Whether this movie is marked as favorite.
    public var isFavorite: Bool

    /// Custom sort order preference.
    public var sortOrder: Int

    /// Last accessed timestamp.
    public var lastAccessedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        year: Int? = nil,
        genre: String? = nil,
        duration: TimeInterval? = nil,
        streamURLString: String,
        posterURLString: String? = nil,
        isFavorite: Bool = false,
        sortOrder: Int = 0,
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.genre = genre
        self.duration = duration
        self.streamURLString = streamURLString
        self.posterURLString = posterURLString
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
        self.lastAccessedAt = lastAccessedAt
    }

    public var streamURL: URL? {
        URL(string: streamURLString)
    }

    public var posterURL: URL? {
        posterURLString.flatMap { URL(string: $0) }
    }

    /// Converts this record to a Movie struct.
    public func toMovie() -> Movie? {
        guard let url = streamURL else { return nil }
        return Movie(
            id: id,
            title: title,
            year: year,
            genre: genre,
            duration: duration,
            streamURL: url,
            posterURL: posterURL
        )
    }
}
