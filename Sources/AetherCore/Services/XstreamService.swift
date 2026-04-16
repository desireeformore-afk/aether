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
public struct XstreamCategory: Decodable, Sendable, Identifiable {
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
        let streamURL = credentials.baseURL
            .appendingPathComponent("live")
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(id).\(ext)")

        return Channel(
            id: UUID(),
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
        let streamURL = credentials.baseURL
            .appendingPathComponent("movie")
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(id).\(ext)")

        return Channel(
            id: UUID(),
            name: name,
            streamURL: streamURL,
            logoURL: streamIcon.flatMap(URL.init(string:)),
            groupTitle: categoryID ?? "",
            epgId: nil
        )
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
        try await get(queryItems: [
            URLQueryItem(name: "action", value: "get_live_categories")
        ])
    }

    /// Fetches live streams, optionally filtered by `categoryID`.
    public func liveStreams(categoryID: String? = nil) async throws -> [XstreamStream] {
        var items = [URLQueryItem(name: "action", value: "get_live_streams")]
        if let cid = categoryID {
            items.append(URLQueryItem(name: "category_id", value: cid))
        }
        return try await get(queryItems: items)
    }

    /// Returns all live streams as `[Channel]`.
    public func channels(categoryID: String? = nil) async throws -> [Channel] {
        let streams = try await liveStreams(categoryID: categoryID)
        return streams.map { $0.toChannel(credentials: credentials) }
    }

    // MARK: - VOD

    /// Fetches all VOD categories.
    public func vodCategories() async throws -> [XstreamCategory] {
        try await get(queryItems: [
            URLQueryItem(name: "action", value: "get_vod_categories")
        ])
    }

    /// Fetches VOD streams, optionally filtered by `categoryID`.
    public func vodStreams(categoryID: String? = nil) async throws -> [XstreamVOD] {
        var items = [URLQueryItem(name: "action", value: "get_vod_streams")]
        if let cid = categoryID {
            items.append(URLQueryItem(name: "category_id", value: cid))
        }
        return try await get(queryItems: items)
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

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw XstreamError.decodingError(error)
        }
    }
}

// MARK: - Errors

public enum XstreamError: Error, Sendable {
    case invalidURL
    case httpError(Int)
    case decodingError(Error)
    case unauthorized
}
