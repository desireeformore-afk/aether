import Foundation

/// Groups series episodes by series name and provides organized access.
public struct SeriesGrouper: Sendable {

    /// A grouped series with its episodes.
    public struct SeriesGroup: Sendable, Hashable {
        public let seriesName: String
        public let episodes: [Episode]

        public init(seriesName: String, episodes: [Episode]) {
            self.seriesName = seriesName
            self.episodes = episodes
        }

        /// Episodes sorted by season and episode number.
        public var sortedEpisodes: [Episode] {
            episodes.sorted { lhs, rhs in
                if lhs.season != rhs.season {
                    return lhs.season < rhs.season
                }
                return lhs.episode < rhs.episode
            }
        }

        /// Unique seasons in this series.
        public var seasons: [Int] {
            Array(Set(episodes.map { $0.season })).sorted()
        }

        /// Episodes for a specific season.
        public func episodes(forSeason season: Int) -> [Episode] {
            episodes.filter { $0.season == season }.sorted { $0.episode < $1.episode }
        }
    }

    /// Groups channels by series name, extracting episode information.
    ///
    /// - Parameter channels: Channels to group (should have contentType == .series).
    /// - Returns: Array of series groups.
    public static func groupSeries(from channels: [Channel]) -> [SeriesGroup] {
        var seriesDict: [String: [Episode]] = [:]

        for channel in channels where channel.isSeries {
            guard let episodeInfo = M3UParser.parseEpisodeInfo(from: channel.name) else {
                continue
            }

            let episode = Episode(
                seriesName: episodeInfo.seriesName,
                season: episodeInfo.season,
                episode: episodeInfo.episode,
                title: episodeInfo.title,
                streamURL: channel.streamURL,
                thumbnailURL: channel.logoURL
            )

            seriesDict[episodeInfo.seriesName, default: []].append(episode)
        }

        return seriesDict.map { SeriesGroup(seriesName: $0.key, episodes: $0.value) }
            .sorted { $0.seriesName < $1.seriesName }
    }

    /// Converts movie channels to Movie objects.
    ///
    /// - Parameter channels: Channels to convert (should have contentType == .movie).
    /// - Returns: Array of movies.
    public static func extractMovies(from channels: [Channel]) -> [Movie] {
        channels.compactMap { channel in
            guard channel.isMovie else { return nil }

            let movieInfo = M3UParser.parseMovieInfo(from: channel.name)
            let title = movieInfo?.title ?? channel.name
            let year = movieInfo?.year

            return Movie(
                title: title,
                year: year,
                streamURL: channel.streamURL,
                posterURL: channel.logoURL
            )
        }
    }
}
