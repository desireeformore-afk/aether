import Foundation

/// Represents a movie with metadata.
public struct Movie: Identifiable, Sendable, Hashable {
    /// Unique identifier for the movie.
    public let id: UUID

    /// Title of the movie.
    public var title: String

    /// Release year (if available).
    public var year: Int?

    /// Genre (if available).
    public var genre: String?

    /// Duration in seconds (if available).
    public var duration: TimeInterval?

    /// URL of the stream.
    public var streamURL: URL

    /// Optional URL for the movie poster.
    public var posterURL: URL?

    /// Creates a new movie.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - title: Title of the movie.
    ///   - year: Optional release year.
    ///   - genre: Optional genre.
    ///   - duration: Optional duration in seconds.
    ///   - streamURL: URL of the stream.
    ///   - posterURL: Optional poster image URL.
    public init(
        id: UUID = UUID(),
        title: String,
        year: Int? = nil,
        genre: String? = nil,
        duration: TimeInterval? = nil,
        streamURL: URL,
        posterURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.genre = genre
        self.duration = duration
        self.streamURL = streamURL
        self.posterURL = posterURL
    }

    /// Formatted display name with year (e.g., "Movie Title (2024)").
    public var displayName: String {
        if let year = year {
            return "\(title) (\(year))"
        }
        return title
    }
}
