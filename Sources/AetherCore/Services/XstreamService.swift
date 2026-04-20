import Foundation

// MARK: - Xtream Codes API Models

/// Credentials for an Xtream Codes panel.
public struct XstreamCredentials: Sendable {
    public let baseURL: URL
    public let username: String
    public let password: String

    public init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    /// Xtream panel URL, e.g. `http://host:port/player_api.php?username=u&password=p`
    var apiBase: URL {
        baseURL
            .appendingPathComponent("player_api.php")
            .appending(queryItems: [
                URLQueryItem(name: "username", value: username),
                URLQueryItem(name: "password", value: password)
            ])
    }

    /// Builds a stream URL without percent-encoding credentials.
    /// `appendingPathComponent` encodes special chars (e.g. `@` → `%40`),
    /// which breaks servers that expect raw credentials in the path.
    func streamURL(type: String, id: Int, ext: String) -> URL {
        let base = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        let raw = "\(base)/\(type)/\(username)/\(password)/\(id).\(ext)"
        return URL(string: raw) ?? baseURL
    }
}

/// Account info returned by `/player_api.php` (login response).
public struct XstreamUserInfo: Decodable, Sendable {
    public let username: String
    public let status: String
    public let expDate: String?
    public let maxConnections: String?
    public let activeCons: String?

    enum CodingKeys: String, CodingKey {
        case username, status
        case expDate = "exp_date"
        case maxConnections = "max_connections"
        case activeCons = "active_cons"
    }
}

/// A live-stream category from Xtream Codes.
public struct XstreamCategory: Decodable, Sendable, Identifiable, Hashable, Equatable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey {
        case id = "category_id"
        case name = "category_name"
    }
}

/// A live stream entry from Xtream Codes.
public struct XstreamStream: Decodable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let streamIcon: String?
    public let epgChannelID: String?
    public let categoryID: String?
    public let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case id = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case epgChannelID = "epg_channel_id"
        case categoryID = "category_id"
        case containerExtension = "container_extension"
    }

    /// Converts to a `Channel` given the credentials (to build the stream URL).
    public func toChannel(credentials: XstreamCredentials) -> Channel {
        let ext = containerExtension ?? "ts"
        let streamURL = credentials.streamURL(type: "live", id: id, ext: ext)

        // Deterministic UUID from streamID so Favorites/navigation survive re-fetch.
        let deterministicID = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", id))") ?? UUID()

        return Channel(
            id: deterministicID,
            name: name,
            streamURL: streamURL,
            logoURL: streamIcon.flatMap(URL.init(string:)),
            groupTitle: categoryID ?? "",
            epgId: epgChannelID
        )
    }
}

/// A VOD stream entry from Xtream Codes.
public struct XstreamVOD: Decodable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let streamIcon: String?
    public let categoryID: String?
    public let containerExtension: String?
    public let rating: String?

    enum CodingKeys: String, CodingKey {
        case id = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
        case containerExtension = "container_extension"
        case rating
    }

    /// Converts to a `Channel` (VOD playback URL).
    public func toChannel(credentials: XstreamCredentials) -> Channel {
        let ext = containerExtension ?? "mp4"
        let streamURL = credentials.streamURL(type: "movie", id: id, ext: ext)

        // Deterministic UUID from stream_id (VOD namespace offset: 0x800000000000).
        let vodID = id + 0x800000000000
        let deterministicID = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", vodID))") ?? UUID()

        return Channel(
            id: deterministicID,
            name: name,
            streamURL: streamURL,
            logoURL: streamIcon.flatMap(URL.init(string:)),
            groupTitle: categoryID ?? "",
            epgId: nil,
            contentType: .movie
        )
    }
}

/// A series category from Xtream Codes.
public struct XstreamSeriesCategory: Decodable, Sendable, Identifiable, Hashable, Equatable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey {
        case id = "category_id"
        case name = "category_name"
    }
}

/// Top-level series entry (list view).
public struct XstreamSeries: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let cover: String?
    public let plot: String?
    public let cast: String?
    public let director: String?
    public let genre: String?
    public let releaseDate: String?
    public let rating: String?
    public let categoryID: String?

    enum CodingKeys: String, CodingKey {
        case id = "series_id"
        case name, cover, plot, cast, director, genre, rating
        case releaseDate = "releaseDate"
        case categoryID = "category_id"
    }
}

/// Episode within a series season.
public struct XstreamEpisode: Decodable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let season: Int
    public let episodeNum: Int
    public let containerExtension: String?
    public let info: EpisodeInfo?

    public struct EpisodeInfo: Decodable, Sendable {
        public let plot: String?
        public let durationSecs: Int?
        public let rating: String?
        enum CodingKeys: String, CodingKey {
            case plot
            case durationSecs = "duration_secs"
            case rating
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title = "title"
        case season
        case episodeNum = "episode_num"
        case containerExtension = "container_extension"
        case info
    }
}

/// Detailed series info with episodes grouped by season.
public struct XstreamSeriesInfo: Decodable, Sendable {
    public let series: XstreamSeries
    /// Key = season number string ("1", "2", …)
    public let episodes: [String: [XstreamEpisode]]

    enum CodingKeys: String, CodingKey {
        case series = "info"
        case episodes
    }
}

// MARK: - XstreamService

/// Communicates with an Xtream Codes IPTV panel.
public actor XstreamService {

    private let credentials: XstreamCredentials
    private let session: URLSession

    public init(credentials: XstreamCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: - Account

    /// Verifies credentials and returns account info.
    public func login() async throws -> XstreamUserInfo {
        struct LoginResponse: Decodable {
            let userInfo: XstreamUserInfo
            enum CodingKeys: String, CodingKey { case userInfo = "user_info" }
        }
        let response: LoginResponse = try await get(queryItems: [])
        return response.userInfo
    }

    // MARK: - Live Streams

    /// Fetches all live stream categories.
    public func liveCategories() async throws -> [XstreamCategory] {
        try await getArray(queryItems: [
            URLQueryItem(name: "action", value: "get_live_categories")
        ])
    }

    /// Fetches live streams, optionally filtered by `categoryID`.
    public func liveStreams(categoryID: String? = nil) async throws -> [XstreamStream] {
        var items = [URLQueryItem(name: "action", value: "get_live_streams")]
        if let cid = categoryID {
            items.append(URLQueryItem(name: "category_id", value: cid))
        }
        return try await getArray(queryItems: items)
    }

    /// Returns all live streams as `[Channel]`.
    public func channels(categoryID: String? = nil) async throws -> [Channel] {
        let streams = try await liveStreams(categoryID: categoryID)
        return streams.map { $0.toChannel(credentials: credentials) }
    }

    // MARK: - VOD

    /// Fetches all VOD categories.
    public func vodCategories() async throws -> [XstreamCategory] {
        try await getArray(queryItems: [
            URLQueryItem(name: "action", value: "get_vod_categories")
        ])
    }

    /// Fetches VOD streams, optionally filtered by `categoryID`.
    public func vodStreams(categoryID: String? = nil) async throws -> [XstreamVOD] {
        var items = [URLQueryItem(name: "action", value: "get_vod_streams")]
        if let cid = categoryID {
            items.append(URLQueryItem(name: "category_id", value: cid))
        }
        return try await getArray(queryItems: items)
    }

    // MARK: - Series

    /// Fetches all series categories.
    public func seriesCategories() async throws -> [XstreamSeriesCategory] {
        try await getArray(queryItems: [
            URLQueryItem(name: "action", value: "get_series_categories")
        ])
    }

    /// Fetches series list, optionally filtered by category.
    public func seriesList(categoryID: String? = nil) async throws -> [XstreamSeries] {
        var items = [URLQueryItem(name: "action", value: "get_series")]
        if let cid = categoryID {
            items.append(URLQueryItem(name: "category_id", value: cid))
        }
        return try await getArray(queryItems: items)
    }

    /// Fetches full info + episode list for a series.
    public func seriesInfo(seriesID: Int) async throws -> XstreamSeriesInfo {
        try await get(queryItems: [
            URLQueryItem(name: "action", value: "get_series_info"),
            URLQueryItem(name: "series_id", value: "\(seriesID)")
        ])
    }

    // MARK: - EPG

    /// Returns the short EPG URL for a stream (Xtream's built-in EPG).
    public func shortEPGURL(streamID: Int, limit: Int = 4) -> URL {
        credentials.baseURL
            .appendingPathComponent("player_api.php")
            .appending(queryItems: [
                URLQueryItem(name: "username", value: credentials.username),
                URLQueryItem(name: "password", value: credentials.password),
                URLQueryItem(name: "action", value: "get_short_epg"),
                URLQueryItem(name: "stream_id", value: "\(streamID)"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ])
    }

    /// Returns the full XMLTV EPG URL for all channels.
    public var xmltvEPGURL: URL {
        credentials.baseURL
            .appendingPathComponent("xmltv.php")
            .appending(queryItems: [
                URLQueryItem(name: "username", value: credentials.username),
                URLQueryItem(name: "password", value: credentials.password)
            ])
    }

    // MARK: - Private

    private func get<T: Decodable>(queryItems: [URLQueryItem]) async throws -> T {
        let data = try await fetch(queryItems: queryItems)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            print("[XstreamService] Decode error for \(T.self): \(error)")
            print("[XstreamService] Raw response: \(preview)")
            throw XstreamError.decodingError(error)
        }
    }

    /// Variant for list endpoints: returns [] when the server responds with
    /// `false` or `null` instead of a JSON array (common on panels with no
    /// VOD/Series content enabled).
    private func getArray<T: Decodable>(queryItems: [URLQueryItem]) async throws -> [T] {
        let data = try await fetch(queryItems: queryItems)
        // Xtream panels return the boolean `false` or `null` when the list is
        // empty — neither is decodable as [T], so treat them as empty arrays.
        if let firstByte = data.first,
           firstByte == UInt8(ascii: "f") || firstByte == UInt8(ascii: "n") {
            print("[XstreamService] API returned non-array (false/null) — treating as empty list")
            return []
        }
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            print("[XstreamService] Decode error for [\(T.self)]: \(error)")
            print("[XstreamService] Raw response: \(preview)")
            throw XstreamError.decodingError(error)
        }
    }

    private func fetch(queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: credentials.apiBase, resolvingAgainstBaseURL: false)!
        var existing = components.queryItems ?? []
        existing.append(contentsOf: queryItems)
        components.queryItems = existing

        guard let url = components.url else {
            throw XstreamError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw XstreamError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
        return data
    }
}

// MARK: - Errors

public enum XstreamError: Error, Sendable {
    case invalidURL
    case httpError(Int)
    case decodingError(Error)
    case unauthorized
}
