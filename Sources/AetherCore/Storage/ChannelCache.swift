import Foundation

/// Persists channel lists as JSON files on disk — one file per playlist UUID.
/// Located in: ~/Library/Application Support/Aether/ChannelCache/<uuid>.json
///
/// This avoids SwiftData for large datasets (50k+ records) which would block
/// the main thread. JSON round-trips are fast: ~0.3s for 50k channels.
public actor ChannelCache {

    public static let shared = ChannelCache()

    private let cacheDir: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        cacheDir = appSupport.appendingPathComponent("Aether/ChannelCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Loads cached channels for a playlist. Returns `[]` on miss.
    public func load(playlistID: UUID) -> [Channel] {
        let file = cacheURL(for: playlistID)
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoded = try? JSONDecoder().decode([CachedChannel].self, from: data)
        return decoded?.map(\.channel) ?? []
    }

    /// Saves channels to disk. Non-blocking — runs on actor's executor.
    public func save(channels: [Channel], playlistID: UUID) throws {
        let file = cacheURL(for: playlistID)
        let encodable = channels.map(CachedChannel.init)
        let data = try JSONEncoder().encode(encodable)
        try data.write(to: file, options: .atomic)
    }

    /// Deletes the cache file for a playlist (e.g. on playlist removal).
    public func clear(playlistID: UUID) {
        let file = cacheURL(for: playlistID)
        try? FileManager.default.removeItem(at: file)
    }

    /// Returns the date the cache was last written, or nil if no cache exists.
    public func lastModified(playlistID: UUID) -> Date? {
        let file = cacheURL(for: playlistID)
        return (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    // MARK: - Private

    private func cacheURL(for id: UUID) -> URL {
        cacheDir.appendingPathComponent("\(id.uuidString).json")
    }
}

// MARK: - Codable wrapper

extension ChannelCache {
    /// Lightweight Codable representation of a `Channel` for JSON persistence.
    struct CachedChannel: Codable {
        let id: UUID
        let name: String
        let streamURL: String
        let logoURL: String?
        let groupTitle: String
        let epgId: String?
        let contentType: ContentType

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case streamURL
            case logoURL
            case groupTitle
            case epgId
            case contentType
        }

        init(_ channel: Channel) {
            self.id = channel.id
            self.name = channel.name
            self.streamURL = channel.streamURL.absoluteString
            self.logoURL = channel.logoURL?.absoluteString
            self.groupTitle = channel.groupTitle
            self.epgId = channel.epgId
            self.contentType = channel.contentType
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            streamURL = try c.decode(String.self, forKey: .streamURL)
            logoURL = try c.decodeIfPresent(String.self, forKey: .logoURL)
            groupTitle = try c.decode(String.self, forKey: .groupTitle)
            epgId = try c.decodeIfPresent(String.self, forKey: .epgId)
            contentType = (try? c.decodeIfPresent(ContentType.self, forKey: .contentType)) ?? .liveTV
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(streamURL, forKey: .streamURL)
            try c.encodeIfPresent(logoURL, forKey: .logoURL)
            try c.encode(groupTitle, forKey: .groupTitle)
            try c.encodeIfPresent(epgId, forKey: .epgId)
            try c.encode(contentType, forKey: .contentType)
        }

        var channel: Channel {
            let resolvedStreamURL = URL(string: streamURL) ?? URL(string: "http://invalid.stream")
            return Channel(
                id: id,
                name: name,
                streamURL: resolvedStreamURL ?? URL(fileURLWithPath: "/"),
                logoURL: logoURL.flatMap(URL.init(string:)),
                groupTitle: groupTitle,
                epgId: epgId,
                contentType: contentType
            )
        }
    }
}
