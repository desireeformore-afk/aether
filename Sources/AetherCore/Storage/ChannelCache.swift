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
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Could not locate Application Support directory")
        }
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

/// Lightweight Codable representation of a `Channel` for JSON persistence.
private struct CachedChannel: Codable {
    let id: UUID
    let name: String
    let streamURL: String
    let logoURL: String?
    let groupTitle: String
    let epgId: String?

    init(_ channel: Channel) {
        self.id = channel.id
        self.name = channel.name
        self.streamURL = channel.streamURL.absoluteString
        self.logoURL = channel.logoURL?.absoluteString
        self.groupTitle = channel.groupTitle
        self.epgId = channel.epgId
    }

    var channel: Channel {
        guard let streamURL = URL(string: streamURL) else {
            // Fallback to a placeholder URL if parsing fails
            return Channel(
                id: id,
                name: name,
                streamURL: URL(string: "http://invalid.stream")!,
                logoURL: logoURL.flatMap(URL.init(string:)),
                groupTitle: groupTitle,
                epgId: epgId
            )
        }
        return Channel(
            id: id,
            name: name,
            streamURL: streamURL,
            logoURL: logoURL.flatMap(URL.init(string:)),
            groupTitle: groupTitle,
            epgId: epgId
        )
    }
}
