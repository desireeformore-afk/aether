import Foundation

/// Represents a series episode with season and episode information.
public struct Episode: Identifiable, Sendable, Hashable {
    /// Unique identifier for the episode.
    public let id: UUID

    /// Name of the series this episode belongs to.
    public var seriesName: String

    /// Season number.
    public var season: Int

    /// Episode number within the season.
    public var episode: Int

    /// Title of the episode (if available).
    public var title: String?

    /// URL of the stream.
    public var streamURL: URL

    /// Optional URL for the episode thumbnail.
    public var thumbnailURL: URL?

    /// Creates a new episode.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - seriesName: Name of the series.
    ///   - season: Season number.
    ///   - episode: Episode number.
    ///   - title: Optional episode title.
    ///   - streamURL: URL of the stream.
    ///   - thumbnailURL: Optional thumbnail image URL.
    public init(
        id: UUID = UUID(),
        seriesName: String,
        season: Int,
        episode: Int,
        title: String? = nil,
        streamURL: URL,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.seriesName = seriesName
        self.season = season
        self.episode = episode
        self.title = title
        self.streamURL = streamURL
        self.thumbnailURL = thumbnailURL
    }

    /// Formatted display name (e.g., "S01E01" or "S01E01 - Episode Title").
    public var displayName: String {
        let seasonEpisode = String(format: "S%02dE%02d", season, episode)
        if let title = title, !title.isEmpty {
            return "\(seasonEpisode) - \(title)"
        }
        return seasonEpisode
    }
}
