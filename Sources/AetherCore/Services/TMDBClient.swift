import Foundation

/// Central Network Client for TMDB Synchronization and "Hidden Gems" aggregation.
public actor TMDBClient {
    public static let shared = TMDBClient()
    
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBaseURL = "https://image.tmdb.org/t/p/"
    
    /// User injected TMDB key from settings or process environment.
    private var apiKey: String {
        let stored = UserDefaults.standard.string(forKey: "tmdbAPIKey") ?? ""
        if !stored.isEmpty { return stored }
        return ProcessInfo.processInfo.environment["TMDB_API_KEY"] ?? ""
    }
    
    /// Cache memory for fast retrieval
    private var cache: [String: TMDBMedia] = [:]
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }
    
    public enum MediaType: Sendable {
        case movie, tv
    }
    
    // MARK: - API Methods
    
    /// Resolves official Media from TMDB using the raw title string
    private func searchMedia(title: String, year: Int? = nil, type: MediaType) async throws -> TMDBMedia? {
        if apiKey.isEmpty {
            print("[TMDBClient] API Key missing. Skipping TMDB fetch.")
            return nil
        }
        
        let cacheKey = "\(title)-\(year ?? 0)-\(type)"
        if let cached = cache[cacheKey] {
            return cached
        }
        
        let typePath = type == .movie ? "search/movie" : "search/tv"
        var urlComponents = URLComponents(string: "\(baseURL)/\(typePath)")!
        var queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "language", value: "pl-PL") // Enforce regional translation sync
        ]
        
        if let year = year {
            queryItems.append(URLQueryItem(name: type == .movie ? "primary_release_year" : "first_air_date_year", value: String(year)))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else { return nil }
        
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let wrapper = try decoder.decode(TMDBSearchResponse.self, from: data)
            
            if let first = wrapper.results.first {
                cache[cacheKey] = first
                return first
            }
            return nil
        } catch {
            print("[TMDBClient] Fetch failed for '\(title)': \(error)")
            return nil
        }
    }

    public func mediaDetails(title: String, year: Int? = nil, type: MediaType) async throws -> TMDBMediaDetails? {
        guard let media = try await searchMedia(title: title, year: year, type: type) else { return nil }
        return TMDBMediaDetails(
            yearString: media.yearString,
            voteAverage: media.voteAverage,
            posterURLString: posterURL(for: media.posterPath)?.absoluteString,
            backdropURLString: backdropURL(for: media.backdropPath)?.absoluteString
        )
    }
    
    /// Generates the absolute URL for fetching the poster
    public func posterURL(for path: String?, width: Int = 500) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        return URL(string: "\(imageBaseURL)w\(width)\(path)")
    }
    
    /// Generates the absolute URL for the cinematic landscape background
    public func backdropURL(for path: String?, width: Int = 1280) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        return URL(string: "\(imageBaseURL)w\(width)\(path)")
    }
}

// MARK: - Models

public struct TMDBSearchResponse: Decodable, Sendable {
    public let results: [TMDBMedia]
}

public struct TMDBMediaDetails: Hashable, Sendable {
    public let yearString: String?
    public let voteAverage: Double?
    public let posterURLString: String?
    public let backdropURLString: String?

    public init(
        yearString: String?,
        voteAverage: Double?,
        posterURLString: String?,
        backdropURLString: String?
    ) {
        self.yearString = yearString
        self.voteAverage = voteAverage
        self.posterURLString = posterURLString
        self.backdropURLString = backdropURLString
    }
}

public struct TMDBMedia: Decodable, Hashable, Sendable {
    public let id: Int
    public let title: String?
    public let name: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let releaseDate: String?
    public let firstAirDate: String?
    
    enum CodingKeys: String, CodingKey, Sendable {
        case id, title, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }
    
    public var displayTitle: String {
        title ?? name ?? "Unknown"
    }
    
    public var yearString: String? {
        if let rel = releaseDate ?? firstAirDate, rel.count >= 4 {
            return String(rel.prefix(4))
        }
        return nil
    }
}
