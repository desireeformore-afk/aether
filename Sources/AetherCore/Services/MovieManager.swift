import Foundation
import SwiftData

/// Manages movie catalog, watch tracking, and filtering.
@MainActor
public final class MovieManager: ObservableObject {

    private let modelContext: ModelContext

    /// Creates a new movie manager.
    ///
    /// - Parameter modelContext: SwiftData model context for persistence.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Movie Catalog

    /// Adds or updates a movie in the catalog.
    ///
    /// - Parameter movie: The movie to add or update.
    public func addOrUpdate(_ movie: Movie) {
        let movieID = movie.id
        let descriptor = FetchDescriptor<MovieRecord>(
            predicate: #Predicate { $0.id == movieID }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = movie.title
            existing.year = movie.year
            existing.genre = movie.genre
            existing.duration = movie.duration
            existing.streamURLString = movie.streamURL.absoluteString
            existing.posterURLString = movie.posterURL?.absoluteString
            existing.lastAccessedAt = .now
        } else {
            let record = MovieRecord(
                id: movie.id,
                title: movie.title,
                year: movie.year,
                genre: movie.genre,
                duration: movie.duration,
                streamURLString: movie.streamURL.absoluteString,
                posterURLString: movie.posterURL?.absoluteString,
                lastAccessedAt: .now
            )
            modelContext.insert(record)
        }

        try? modelContext.save()
    }

    /// Retrieves a movie record by ID.
    ///
    /// - Parameter id: Movie identifier.
    /// - Returns: Movie record if found.
    public func movieRecord(for id: UUID) -> MovieRecord? {
        let movieID = id
        let descriptor = FetchDescriptor<MovieRecord>(
            predicate: #Predicate { $0.id == movieID }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Retrieves all movies in the catalog.
    ///
    /// - Returns: Array of movie records.
    public func allMovies() -> [MovieRecord] {
        let descriptor = FetchDescriptor<MovieRecord>(
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Watch Progress

    /// Updates watch progress for a movie.
    ///
    /// - Parameters:
    ///   - movie: The movie being watched.
    ///   - position: Current playback position in seconds.
    ///   - duration: Total duration in seconds (if known).
    public func updateProgress(
        for movie: Movie,
        position: TimeInterval,
        duration: TimeInterval?
    ) {
        let completionPercent = duration.map { position / $0 } ?? 0
        let isCompleted = completionPercent >= 0.9

        let movieID = movie.id
        let descriptor = FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { $0.contentID == movieID }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastPosition = position
            existing.duration = duration
            existing.completionPercent = completionPercent
            existing.isCompleted = isCompleted
            existing.lastWatchedAt = .now
        } else {
            let record = WatchProgressRecord(
                contentID: movie.id,
                contentType: "movie",
                streamURLString: movie.streamURL.absoluteString,
                lastPosition: position,
                duration: duration,
                completionPercent: completionPercent,
                isCompleted: isCompleted,
                lastWatchedAt: .now,
                movieTitle: movie.title
            )
            modelContext.insert(record)
        }

        try? modelContext.save()
        addOrUpdate(movie)
    }

    /// Retrieves watch progress for a movie.
    ///
    /// - Parameter movie: The movie to query.
    /// - Returns: Watch progress record if found.
    public func progress(for movie: Movie) -> WatchProgressRecord? {
        let movieID = movie.id
        let descriptor = FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { $0.contentID == movieID }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Marks a movie as completed.
    ///
    /// - Parameter movie: The movie to mark as completed.
    public func markCompleted(_ movie: Movie) {
        updateProgress(for: movie, position: 0, duration: 0)
        if let record = progress(for: movie) {
            record.isCompleted = true
            record.completionPercent = 1.0
            try? modelContext.save()
        }
    }

    // MARK: - Favorites

    /// Toggles favorite status for a movie.
    ///
    /// - Parameter movie: The movie to toggle.
    public func toggleFavorite(_ movie: Movie) {
        addOrUpdate(movie)
        if let record = movieRecord(for: movie.id) {
            record.isFavorite.toggle()
            try? modelContext.save()
        }
    }

    /// Checks if a movie is marked as favorite.
    ///
    /// - Parameter movie: The movie to check.
    /// - Returns: True if favorite, false otherwise.
    public func isFavorite(_ movie: Movie) -> Bool {
        movieRecord(for: movie.id)?.isFavorite ?? false
    }

    /// Retrieves all favorite movies.
    ///
    /// - Returns: Array of favorite movie records.
    public func favorites() -> [MovieRecord] {
        let descriptor = FetchDescriptor<MovieRecord>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Filtering

    /// Filters movies by genre.
    ///
    /// - Parameter genre: Genre to filter by.
    /// - Returns: Array of movie records matching the genre.
    public func movies(byGenre genre: String) -> [MovieRecord] {
        let genreValue = genre
        let descriptor = FetchDescriptor<MovieRecord>(
            predicate: #Predicate { $0.genre == genreValue },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Filters movies by year.
    ///
    /// - Parameter year: Release year to filter by.
    /// - Returns: Array of movie records from that year.
    public func movies(byYear year: Int) -> [MovieRecord] {
        let yearValue = year
        let descriptor = FetchDescriptor<MovieRecord>(
            predicate: #Predicate { $0.year == yearValue },
            sortBy: [SortDescriptor(\\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Retrieves unwatched movies.
    ///
    /// - Returns: Array of movie records that haven't been watched.
    public func unwatchedMovies() -> [MovieRecord] {
        let allMovies = allMovies()
        let watchedIDs = Set(watchedMovies().map { $0.id })
        return allMovies.filter { !watchedIDs.contains($0.id) }
    }

    /// Retrieves watched movies.
    ///
    /// - Returns: Array of movie records that have been watched.
    public func watchedMovies() -> [MovieRecord] {
        let descriptor = FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { $0.contentType == "movie" && $0.isCompleted }
        )
        let progressRecords = (try? modelContext.fetch(descriptor)) ?? []
        let watchedIDs = Set(progressRecords.map { $0.contentID })

        return allMovies().filter { watchedIDs.contains($0.id) }
    }

    /// Retrieves movies in progress (started but not completed).
    ///
    /// - Returns: Array of watch progress records sorted by last watched date.
    public func continueWatching() -> [WatchProgressRecord] {
        let descriptor = FetchDescriptor<WatchProgressRecord>(
            predicate: #Predicate { record in
                record.contentType == "movie" && !record.isCompleted && record.lastPosition > 0
            },
            sortBy: [SortDescriptor(\.lastWatchedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Sorting

    /// Retrieves all unique genres from the catalog.
    ///
    /// - Returns: Sorted array of genre names.
    public func allGenres() -> [String] {
        let movies = allMovies()
        let genres = Set(movies.compactMap { $0.genre })
        return genres.sorted()
    }

    /// Retrieves all unique years from the catalog.
    ///
    /// - Returns: Sorted array of years (descending).
    public func allYears() -> [Int] {
        let movies = allMovies()
        let years = Set(movies.compactMap { $0.year })
        return years.sorted(by: >)
    }

    /// Updates custom sort order for a movie.
    ///
    /// - Parameters:
    ///   - movie: The movie to update.
    ///   - sortOrder: New sort order value.
    public func updateSortOrder(for movie: Movie, sortOrder: Int) {
        addOrUpdate(movie)
        if let record = movieRecord(for: movie.id) {
            record.sortOrder = sortOrder
            try? modelContext.save()
        }
    }

    /// Retrieves movies sorted by custom sort order.
    ///
    /// - Returns: Array of movie records sorted by sortOrder.
    public func moviesByCustomOrder() -> [MovieRecord] {
        let descriptor = FetchDescriptor<MovieRecord>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Recently Accessed

    /// Retrieves recently accessed movies.
    ///
    /// - Parameter limit: Maximum number of movies to return. Defaults to 10.
    /// - Returns: Array of movie records sorted by last accessed date.
    public func recentlyAccessed(limit: Int = 10) -> [MovieRecord] {
        let descriptor = FetchDescriptor<MovieRecord>(
            predicate: #Predicate { $0.lastAccessedAt != nil },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        let results = (try? modelContext.fetch(descriptor)) ?? []
        return Array(results.prefix(limit))
    }
}
