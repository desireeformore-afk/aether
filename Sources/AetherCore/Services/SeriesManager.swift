import Foundation
import SwiftData

/// Manages series episodes, watch progress, and viewing recommendations.
@MainActor
@Observable
6|public final class SeriesManager {

    private let modelContext: ModelContext

    /// Creates a new series manager.
    ///
    /// - Parameter modelContext: SwiftData model context for persistence.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Watch Progress

    /// Updates watch progress for an episode.
    ///
    /// - Parameters:
    ///   - episode: The episode being watched.
    ///   - position: Current playback position in seconds.
    ///   - duration: Total duration in seconds (if known).
    public func updateProgress(
        for episode: Episode,
        position: TimeInterval,
        duration: TimeInterval?
    ) {
        let completionPercent = duration.map { position / $0 } ?? 0
        let isCompleted = completionPercent >= 0.9

        let episodeID = episode.id
        let descriptor = FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { $0.contentID == episodeID }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastPosition = position
            existing.duration = duration
            existing.completionPercent = completionPercent
            existing.isCompleted = isCompleted
            existing.lastWatchedAt = .now
        } else {
            let record = WatchProgressRecord(
                contentID: episode.id,
                contentType: "episode",
                streamURLString: episode.streamURL.absoluteString,
                lastPosition: position,
                duration: duration,
                completionPercent: completionPercent,
                isCompleted: isCompleted,
                lastWatchedAt: .now,
                seriesName: episode.seriesName,
                season: episode.season,
                episode: episode.episode
            )
            modelContext.insert(record)
        }

        try? modelContext.save()
        updateSeriesAccess(seriesName: episode.seriesName)
    }

    /// Retrieves watch progress for an episode.
    ///
    /// - Parameter episode: The episode to query.
    /// - Returns: Watch progress record if found.
    public func progress(for episode: Episode) -> WatchProgressRecord? {
        let episodeID = episode.id
        let descriptor = FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { $0.contentID == episodeID }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Marks an episode as completed.
    ///
    /// - Parameter episode: The episode to mark as completed.
    public func markCompleted(_ episode: Episode) {
        updateProgress(for: episode, position: 0, duration: 0)
        if let record = progress(for: episode) {
            record.isCompleted = true
            record.completionPercent = 1.0
            try? modelContext.save()
        }
    }

    // MARK: - Continue Watching

    /// Returns episodes that are in progress (started but not completed).
    ///
    /// - Returns: Array of watch progress records sorted by last watched date.
    public func continueWatching() -> [WatchProgressRecord] {
        let descriptor = FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { record in
                record.contentType == "episode" && !record.isCompleted && record.lastPosition > 0
            },
            sortBy: [SortDescriptor(\.lastWatchedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Next Episode

    /// Suggests the next episode to watch in a series.
    ///
    /// - Parameter series: The series to analyze.
    /// - Returns: The next unwatched episode, or nil if all are watched.
    public func nextEpisode(in series: Series) -> Episode? {
        let sortedEpisodes = series.sortedEpisodes

        for episode in sortedEpisodes {
            if let prog = progress(for: episode), prog.isCompleted {
                continue
            }
            return episode
        }

        return nil
    }

    /// Suggests the next episode after the given episode.
    ///
    /// - Parameters:
    ///   - episode: Current episode.
    ///   - allEpisodes: All episodes in the series.
    /// - Returns: The next episode in sequence, or nil if this is the last.
    public func nextEpisode(after episode: Episode, in allEpisodes: [Episode]) -> Episode? {
        let sorted = allEpisodes.sorted { lhs, rhs in
            if lhs.season != rhs.season {
                return lhs.season < rhs.season
            }
            return lhs.episode < rhs.episode
        }

        guard let currentIndex = sorted.firstIndex(where: { $0.id == episode.id }),
              currentIndex + 1 < sorted.count else {
            return nil
        }

        return sorted[currentIndex + 1]
    }

    // MARK: - Series Grouping

    /// Groups episodes by series name.
    ///
    /// - Parameter episodes: Episodes to group.
    /// - Returns: Dictionary mapping series names to their episodes.
    public func groupBySeries(_ episodes: [Episode]) -> [String: [Episode]] {
        Dictionary(grouping: episodes) { $0.seriesName }
    }

    /// Groups episodes by season within a series.
    ///
    /// - Parameter episodes: Episodes to group (should be from same series).
    /// - Returns: Dictionary mapping season numbers to their episodes.
    public func groupBySeason(_ episodes: [Episode]) -> [Int: [Episode]] {
        Dictionary(grouping: episodes) { $0.season }
    }

    // MARK: - Series Metadata

    /// Retrieves or creates a series record.
    ///
    /// - Parameter seriesName: Name of the series.
    /// - Returns: The series record.
    public func seriesRecord(for seriesName: String) -> SeriesRecord {
        let name = seriesName
        let descriptor = FetchDescriptor<SeriesRecord>(
            predicate: #Predicate { $0.name == name }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let record = SeriesRecord(name: seriesName)
        modelContext.insert(record)
        try? modelContext.save()
        return record
    }

    /// Updates the last accessed timestamp for a series.
    ///
    /// - Parameter seriesName: Name of the series.
    private func updateSeriesAccess(seriesName: String) {
        let record = seriesRecord(for: seriesName)
        record.lastAccessedAt = .now
        try? modelContext.save()
    }

    /// Toggles favorite status for a series.
    ///
    /// - Parameter seriesName: Name of the series.
    public func toggleFavorite(for seriesName: String) {
        let record = seriesRecord(for: seriesName)
        record.isFavorite.toggle()
        try? modelContext.save()
    }

    /// Returns all favorite series.
    ///
    /// - Returns: Array of favorite series records.
    public func favoriteSeries() -> [SeriesRecord] {
        let descriptor = FetchDescriptor<SeriesRecord>(
            predicate: #Predicate { $0.isFavorite }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Statistics

    /// Calculates watch statistics for a series.
    ///
    /// - Parameters:
    ///   - seriesName: Name of the series.
    ///   - totalEpisodes: Total number of episodes in the series.
    /// - Returns: Tuple of (watched count, in-progress count, unwatched count).
    public func watchStats(for seriesName: String, totalEpisodes: Int) -> (watched: Int, inProgress: Int, unwatched: Int) {
        let name = seriesName
        let descriptor = FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { $0.seriesName == name }
        )

        guard let records = try? modelContext.fetch(descriptor) else {
            return (0, 0, totalEpisodes)
        }

        let watched = records.filter { $0.isCompleted }.count
        let inProgress = records.filter { !$0.isCompleted && $0.lastPosition > 0 }.count
        let unwatched = totalEpisodes - watched - inProgress

        return (watched, inProgress, max(0, unwatched))
    }
}
