import Foundation

/// Represents a series with metadata.
public struct Series: Identifiable, Sendable, Hashable {
    /// Unique identifier for the series.
    public let id: UUID

    /// Name of the series.
    public var name: String

    /// Optional poster URL.
    public var posterURL: URL?

    /// All episodes in this series.
    public var episodes: [Episode]

    /// Creates a new series.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - name: Name of the series.
    ///   - posterURL: Optional poster image URL.
    ///   - episodes: Episodes in this series.
    public init(
        id: UUID = UUID(),
        name: String,
        posterURL: URL? = nil,
        episodes: [Episode] = []
    ) {
        self.id = id
        self.name = name
        self.posterURL = posterURL
        self.episodes = episodes
    }

    /// Unique seasons in this series.
    public var seasons: [Int] {
        Array(Set(episodes.map { $0.season })).sorted()
    }

    /// Episodes for a specific season.
    public func episodes(forSeason season: Int) -> [Episode] {
        episodes.filter { $0.season == season }.sorted { $0.episode < $1.episode }
    }

    /// All episodes sorted by season and episode number.
    public var sortedEpisodes: [Episode] {
        episodes.sorted { lhs, rhs in
            if lhs.season != rhs.season {
                return lhs.season < rhs.season
            }
            return lhs.episode < rhs.episode
        }
    }
}
