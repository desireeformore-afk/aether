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
    public func streamURL(type: String, id: Int, ext: String) -> URL {
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
    /// Backward-compatible display category. Prefer this for UI labels.
    public let categoryName: String?
    /// Raw category name as returned by the provider/category endpoint.
    public let rawCategoryName: String?
    /// Structured category metadata for catalog builders and search.
    public let normalizedCategory: NormalizedContentCategory?
    public let containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case id = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case epgChannelID = "epg_channel_id"
        case categoryID = "category_id"
        case categoryName = "category_name"
        case containerExtension = "container_extension"
    }

    public init(
        id: Int,
        name: String,
        streamIcon: String?,
        epgChannelID: String?,
        categoryID: String?,
        categoryName: String?,
        rawCategoryName: String? = nil,
        normalizedCategory: NormalizedContentCategory? = nil,
        containerExtension: String?
    ) {
        self.id = id
        self.name = name
        self.streamIcon = streamIcon
        self.epgChannelID = epgChannelID
        self.categoryID = categoryID
        self.containerExtension = containerExtension

        let rawName = rawCategoryName ?? categoryName
        let resolvedCategory = normalizedCategory ?? CategoryNormalizer.normalize(
            rawID: categoryID,
            rawName: rawName,
            provider: .xtream,
            contentType: .liveTV
        )
        self.rawCategoryName = rawName
        self.normalizedCategory = resolvedCategory
        self.categoryName = resolvedCategory.displayName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(FlexInt.self, forKey: .id).value
        let name = try c.decode(String.self, forKey: .name)
        let streamIcon = try c.decodeIfPresent(String.self, forKey: .streamIcon)
        let epgChannelID = try c.decodeIfPresent(String.self, forKey: .epgChannelID)
        let categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        let categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        let containerExtension = try c.decodeIfPresent(String.self, forKey: .containerExtension)
        self.init(
            id: id,
            name: name,
            streamIcon: streamIcon,
            epgChannelID: epgChannelID,
            categoryID: categoryID,
            categoryName: categoryName,
            rawCategoryName: categoryName,
            containerExtension: containerExtension
        )
    }

    public func resolvingCategory(_ category: NormalizedContentCategory?) -> XstreamStream {
        guard let category else { return self }
        return XstreamStream(
            id: id,
            name: name,
            streamIcon: streamIcon,
            epgChannelID: epgChannelID,
            categoryID: categoryID,
            categoryName: category.displayName,
            rawCategoryName: category.raw.rawName ?? rawCategoryName ?? categoryName,
            normalizedCategory: category,
            containerExtension: containerExtension
        )
    }

    /// Converts to a `Channel` given the credentials (to build the stream URL).
    public func toChannel(credentials: XstreamCredentials, categoryName: String? = nil) -> Channel {
        let ext = containerExtension ?? "ts"
        let streamURL = credentials.streamURL(type: "live", id: id, ext: ext)
        let rawCategoryName = categoryName ?? self.categoryName ?? categoryID ?? ""
        let category = CategoryNormalizer.normalize(
            rawID: categoryID,
            rawName: rawCategoryName,
            provider: .xtream,
            contentType: .liveTV
        )
        let groupTitle = rawCategoryName.isEmpty ? "" : category.displayName

        // Deterministic UUID from streamID so Favorites/navigation survive re-fetch.
        let deterministicID = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", id))") ?? UUID()

        return Channel(
            id: deterministicID,
            name: name,
            streamURL: streamURL,
            logoURL: streamIcon.flatMap(URL.init(string:)),
            groupTitle: groupTitle,
            epgId: epgChannelID
        )
    }
}

/// A VOD stream entry from Xtream Codes.
public struct XstreamVOD: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let streamIcon: String?
    public let categoryID: String?
    /// Backward-compatible display category. Prefer this for UI labels.
    public let categoryName: String?
    /// Raw category name as returned by the provider/category endpoint.
    public let rawCategoryName: String?
    /// Structured category metadata for catalog builders and search.
    public let normalizedCategory: NormalizedContentCategory?
    public let containerExtension: String?
    public let rating: String?

    enum CodingKeys: String, CodingKey {
        case id = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
        case categoryName = "category_name"
        case containerExtension = "container_extension"
        case rating
    }

    public init(
        id: Int,
        name: String,
        streamIcon: String?,
        categoryID: String?,
        categoryName: String?,
        rawCategoryName: String? = nil,
        normalizedCategory: NormalizedContentCategory? = nil,
        containerExtension: String?,
        rating: String?
    ) {
        self.id = id
        self.name = name
        self.streamIcon = streamIcon
        self.categoryID = categoryID
        self.containerExtension = containerExtension
        self.rating = rating

        let rawName = rawCategoryName ?? categoryName
        let resolvedCategory = normalizedCategory ?? CategoryNormalizer.normalize(
            rawID: categoryID,
            rawName: rawName,
            provider: .xtream,
            contentType: .movie
        )
        self.rawCategoryName = rawName
        self.normalizedCategory = resolvedCategory
        self.categoryName = resolvedCategory.displayName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(FlexInt.self, forKey: .id).value
        let name = try c.decode(String.self, forKey: .name)
        let streamIcon = try c.decodeIfPresent(String.self, forKey: .streamIcon)
        let categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        let categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        let containerExtension = try c.decodeIfPresent(String.self, forKey: .containerExtension)
        let rating = try c.decodeIfPresent(String.self, forKey: .rating)
        self.init(
            id: id,
            name: name,
            streamIcon: streamIcon,
            categoryID: categoryID,
            categoryName: categoryName,
            rawCategoryName: categoryName,
            containerExtension: containerExtension,
            rating: rating
        )
    }

    public func resolvingCategory(_ category: NormalizedContentCategory?) -> XstreamVOD {
        guard let category else { return self }
        return XstreamVOD(
            id: id,
            name: name,
            streamIcon: streamIcon,
            categoryID: categoryID,
            categoryName: category.displayName,
            rawCategoryName: category.raw.rawName ?? rawCategoryName ?? categoryName,
            normalizedCategory: category,
            containerExtension: containerExtension,
            rating: rating
        )
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
            groupTitle: categoryName ?? categoryID ?? "",
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

/// Decodes a JSON value that may be either an Int or a numeric String.
private struct FlexInt: Decodable {
    let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i; return }
        if let s = try? c.decode(String.self), let i = Int(s) { value = i; return }
        value = 0
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
    /// Backward-compatible display category. Prefer this for UI labels.
    public let categoryName: String?
    /// Raw category name as returned by the provider/category endpoint.
    public let rawCategoryName: String?
    /// Structured category metadata for catalog builders and search.
    public let normalizedCategory: NormalizedContentCategory?

    enum CodingKeys: String, CodingKey {
        case id = "series_id"
        case name, cover, plot, cast, director, genre, rating
        case releaseDate = "releaseDate"
        case categoryID = "category_id"
        case categoryName = "category_name"
    }
}

extension XstreamSeries {
    public init(
        id: Int,
        name: String,
        cover: String?,
        plot: String?,
        cast: String?,
        director: String?,
        genre: String?,
        releaseDate: String?,
        rating: String?,
        categoryID: String?,
        categoryName: String?,
        rawCategoryName: String? = nil,
        normalizedCategory: NormalizedContentCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.cover = cover
        self.plot = plot
        self.cast = cast
        self.director = director
        self.genre = genre
        self.releaseDate = releaseDate
        self.rating = rating
        self.categoryID = categoryID

        let rawName = rawCategoryName ?? categoryName
        let resolvedCategory = normalizedCategory ?? CategoryNormalizer.normalize(
            rawID: categoryID,
            rawName: rawName,
            provider: .xtream,
            contentType: .series
        )
        self.rawCategoryName = rawName
        self.normalizedCategory = resolvedCategory
        self.categoryName = resolvedCategory.displayName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(FlexInt.self, forKey: .id).value
        let name = try c.decode(String.self, forKey: .name)
        let cover = try c.decodeIfPresent(String.self, forKey: .cover)
        let plot = try c.decodeIfPresent(String.self, forKey: .plot)
        let cast = try c.decodeIfPresent(String.self, forKey: .cast)
        let director = try c.decodeIfPresent(String.self, forKey: .director)
        let genre = try c.decodeIfPresent(String.self, forKey: .genre)
        let releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        let rating = try c.decodeIfPresent(String.self, forKey: .rating)
        let categoryID = try c.decodeIfPresent(String.self, forKey: .categoryID)
        let categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        self.init(
            id: id,
            name: name,
            cover: cover,
            plot: plot,
            cast: cast,
            director: director,
            genre: genre,
            releaseDate: releaseDate,
            rating: rating,
            categoryID: categoryID,
            categoryName: categoryName,
            rawCategoryName: categoryName
        )
    }

    public func resolvingCategory(_ category: NormalizedContentCategory?) -> XstreamSeries {
        guard let category else { return self }
        return XstreamSeries(
            id: id,
            name: name,
            cover: cover,
            plot: plot,
            cast: cast,
            director: director,
            genre: genre,
            releaseDate: releaseDate,
            rating: rating,
            categoryID: categoryID,
            categoryName: category.displayName,
            rawCategoryName: category.raw.rawName ?? rawCategoryName ?? categoryName,
            normalizedCategory: category
        )
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

extension XstreamEpisode {
    /// Converts this episode to a `Channel` for playback.
    public func toChannel(credentials: XstreamCredentials, seriesName: String = "") -> Channel {
        let ext = containerExtension ?? "mp4"
        let streamURL = credentials.streamURL(type: "series", id: id, ext: ext)
        let seriesOffset = id + 0x400000000000
        let deterministicID = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", seriesOffset))") ?? UUID()
        let episodeName = title.isEmpty ? "S\(season)E\(episodeNum)" : title
        let channelName = seriesName.isEmpty ? episodeName : "\(seriesName) — \(episodeName)"
        return Channel(
            id: deterministicID,
            name: channelName,
            streamURL: streamURL,
            groupTitle: "",
            contentType: .series
        )
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(FlexInt.self, forKey: .id).value
        title = try c.decode(String.self, forKey: .title)
        season = (try? c.decodeIfPresent(FlexInt.self, forKey: .season))?.value ?? 0
        episodeNum = (try? c.decodeIfPresent(FlexInt.self, forKey: .episodeNum))?.value ?? 0
        containerExtension = try? c.decodeIfPresent(String.self, forKey: .containerExtension)
        info = try? c.decodeIfPresent(EpisodeInfo.self, forKey: .info)
    }
}

/// Detailed series info with episodes grouped by season.
public struct XstreamSeriesInfo: Decodable, Sendable {
    public let series: XstreamSeries
    /// Key = season number string ("1", "2", …)
    public let episodes: [String: [XstreamEpisode]]

    public init(series: XstreamSeries, episodes: [String: [XstreamEpisode]]) {
        self.series = series
        self.episodes = episodes
    }

    private struct SeriesInfoBody: Decodable {
        let name: String
        let cover: String?
        let plot: String?
        let cast: String?
        let director: String?
        let genre: String?
        let releaseDate: String?
        let rating: String?
        let categoryID: String?
        let categoryName: String?
        // series_id may appear here on some servers but is unreliable
        let seriesID: FlexInt?

        enum CodingKeys: String, CodingKey {
            case name, cover, plot, cast, director, genre, rating
            case releaseDate = "releaseDate"
            case categoryID = "category_id"
            case categoryName = "category_name"
            case seriesID = "series_id"
        }
    }

    private enum RootKeys: String, CodingKey {
        case info, episodes
        case seriesID = "series_id"
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let body = try root.decode(SeriesInfoBody.self, forKey: .info)
        let rootSeriesID = try root.decodeIfPresent(FlexInt.self, forKey: .seriesID)?.value
        let resolvedID = rootSeriesID ?? body.seriesID?.value ?? 0
        series = XstreamSeries(
            id: resolvedID,
            name: body.name,
            cover: body.cover,
            plot: body.plot,
            cast: body.cast,
            director: body.director,
            genre: body.genre,
            releaseDate: body.releaseDate,
            rating: body.rating,
            categoryID: body.categoryID,
            categoryName: body.categoryName
        )
        episodes = (try? root.decode([String: [XstreamEpisode]].self, forKey: .episodes)) ?? [:]
    }
}

// MARK: - XstreamService

/// Communicates with an Xtream Codes IPTV panel.
public actor XstreamService {

    private let credentials: XstreamCredentials
    private let session: URLSession

    public var cachedVods: [XstreamVOD] = []
    public var cachedSeries: [XstreamSeries] = []

    private var cachedLiveCategoryMap: [String: NormalizedContentCategory]?
    private var cachedVODCategoryMap: [String: NormalizedContentCategory]?
    private var cachedSeriesCategoryMap: [String: NormalizedContentCategory]?

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
        let categories: [XstreamCategory] = try await getArray(queryItems: [
            URLQueryItem(name: "action", value: "get_live_categories")
        ])
        cachedLiveCategoryMap = Self.normalizedCategoryMap(
            categories,
            contentType: .liveTV
        )
        return categories
    }

    /// Fetches live streams, optionally filtered by `categoryID`.
    public func liveStreams(categoryID: String? = nil) async throws -> [XstreamStream] {
        var items = [URLQueryItem(name: "action", value: "get_live_streams")]
        if let cid = categoryID {
            items.append(URLQueryItem(name: "category_id", value: cid))
        }
        let rawResult: [XstreamStream] = try await getArray(queryItems: items)
        let categoryMap = (try? await liveCategoryMap()) ?? [:]
        return rawResult.map { stream in
            stream.resolvingCategory(stream.categoryID.flatMap { categoryMap[$0] })
        }
    }

    /// Returns all live streams as `[Channel]`.
    public func channels(categoryID: String? = nil) async throws -> [Channel] {
        let streams = try await liveStreams(categoryID: categoryID)
        return streams.map { $0.toChannel(credentials: credentials) }
    }

    // MARK: - VOD

    /// Fetches all VOD categories.
    public func vodCategories() async throws -> [XstreamCategory] {
        let categories: [XstreamCategory] = try await getArray(queryItems: [
            URLQueryItem(name: "action", value: "get_vod_categories")
        ])
        cachedVODCategoryMap = Self.normalizedCategoryMap(
            categories,
            contentType: .movie
        )
        return categories
    }

    /// Fetches VOD streams, optionally filtered by `categoryID`.
    public func vodStreams(categoryID: String? = nil) async throws -> [XstreamVOD] {
        var items = [URLQueryItem(name: "action", value: "get_vod_streams")]
        if let cid = categoryID {
            items.append(URLQueryItem(name: "category_id", value: cid))
        }
        let rawResult: [XstreamVOD] = try await getArray(queryItems: items)
        let categoryMap = (try? await vodCategoryMap()) ?? [:]
        let result = rawResult.map { vod in
            vod.resolvingCategory(vod.categoryID.flatMap { categoryMap[$0] })
        }
        if categoryID == nil { cachedVods = result }
        return result
    }

    /// Loads VODs from the first few clean categories — fast home screen preview.
    /// Much faster than loading all streams; fetches only ~1–2 MB vs 60 MB.
    public func vodStreamsFast() async throws -> [XstreamVOD] {
        let cats = try await vodCategories()
        let cleanCats = cats.filter {
            CategoryNormalizer.isPrimaryCategoryVisible(
                $0.name,
                rawID: $0.id,
                provider: .xtream,
                contentType: .movie
            )
        }
        let topCats = Array(cleanCats.prefix(3))
        guard !topCats.isEmpty else {
            if let first = cats.first {
                return (try? await vodStreams(categoryID: first.id)) ?? []
            }
            return []
        }
        async let r0 = (try? vodStreams(categoryID: topCats[0].id)) ?? []
        async let r1 = topCats.count > 1 ? ((try? vodStreams(categoryID: topCats[1].id)) ?? []) : []
        async let r2 = topCats.count > 2 ? ((try? vodStreams(categoryID: topCats[2].id)) ?? []) : []
        return await r0 + r1 + r2
    }

    /// Searches cached VODs by title (case-insensitive). Returns all if query is empty.
    public func searchVODs(query: String) -> [XstreamVOD] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return cachedVods }
        return cachedVods.filter { $0.name.lowercased().contains(q) }
    }

    /// Searches cached series by title (case-insensitive). Returns all if query is empty.
    public func searchSeries(query: String) -> [XstreamSeries] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return cachedSeries }
        return cachedSeries.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: - Series

    /// Fetches all series categories.
    public func seriesCategories() async throws -> [XstreamSeriesCategory] {
        let categories: [XstreamSeriesCategory] = try await getArray(queryItems: [
            URLQueryItem(name: "action", value: "get_series_categories")
        ])
        cachedSeriesCategoryMap = Self.normalizedSeriesCategoryMap(categories)
        return categories
    }

    /// Fetches series list, optionally filtered by category.
    public func seriesList(categoryID: String? = nil) async throws -> [XstreamSeries] {
        var items = [URLQueryItem(name: "action", value: "get_series")]
        if let cid = categoryID {
            items.append(URLQueryItem(name: "category_id", value: cid))
        }
        let rawResult: [XstreamSeries] = try await getArray(queryItems: items)
        let categoryMap = (try? await seriesCategoryMap()) ?? [:]
        let result = rawResult.map { series in
            series.resolvingCategory(series.categoryID.flatMap { categoryMap[$0] })
        }
        if categoryID == nil { cachedSeries = result }
        return result
    }

    /// Fetches full info + episode list for a series.
    public func seriesInfo(seriesID: Int) async throws -> XstreamSeriesInfo {
        let info: XstreamSeriesInfo = try await get(queryItems: [
            URLQueryItem(name: "action", value: "get_series_info"),
            URLQueryItem(name: "series_id", value: "\(seriesID)")
        ])
        let categoryMap = (try? await seriesCategoryMap()) ?? [:]
        guard let category = info.series.categoryID.flatMap({ categoryMap[$0] }) else {
            return info
        }
        return XstreamSeriesInfo(
            series: info.series.resolvingCategory(category),
            episodes: info.episodes
        )
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

    private func liveCategoryMap() async throws -> [String: NormalizedContentCategory] {
        if let cachedLiveCategoryMap { return cachedLiveCategoryMap }
        _ = try await liveCategories()
        return cachedLiveCategoryMap ?? [:]
    }

    private func vodCategoryMap() async throws -> [String: NormalizedContentCategory] {
        if let cachedVODCategoryMap { return cachedVODCategoryMap }
        _ = try await vodCategories()
        return cachedVODCategoryMap ?? [:]
    }

    private func seriesCategoryMap() async throws -> [String: NormalizedContentCategory] {
        if let cachedSeriesCategoryMap { return cachedSeriesCategoryMap }
        _ = try await seriesCategories()
        return cachedSeriesCategoryMap ?? [:]
    }

    private static func normalizedCategoryMap(
        _ categories: [XstreamCategory],
        contentType: ContentType
    ) -> [String: NormalizedContentCategory] {
        var result: [String: NormalizedContentCategory] = [:]
        for category in categories {
            result[category.id] = CategoryNormalizer.normalize(
                rawID: category.id,
                rawName: category.name,
                provider: .xtream,
                contentType: contentType
            )
        }
        return result
    }

    private static func normalizedSeriesCategoryMap(
        _ categories: [XstreamSeriesCategory]
    ) -> [String: NormalizedContentCategory] {
        var result: [String: NormalizedContentCategory] = [:]
        for category in categories {
            result[category.id] = CategoryNormalizer.normalize(
                rawID: category.id,
                rawName: category.name,
                provider: .xtream,
                contentType: .series
            )
        }
        return result
    }

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
        guard var components = URLComponents(url: credentials.apiBase, resolvingAgainstBaseURL: false) else {
            throw XstreamError.invalidURL
        }
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
