import Foundation

/// Protocol for items that can be synced via iCloud
public protocol SyncableItem: Codable, Identifiable {
    var id: UUID { get }
    var lastModified: Date { get set }
    var syncStatus: SyncStatus { get set }
}

/// Sync status for items
public enum SyncStatus: String, Codable {
    case synced
    case pending
    case conflict
    case error
}

/// Wrapper for synced playlists
public struct SyncedPlaylist: SyncableItem {
    public let id: UUID
    public var lastModified: Date
    public var syncStatus: SyncStatus

    public var name: String
    public var url: String
    public var type: PlaylistType
    public var username: String?
    public var password: String?

    public init(id: UUID = UUID(), name: String, url: String, type: PlaylistType, username: String? = nil, password: String? = nil) {
        self.id = id
        self.lastModified = Date()
        self.syncStatus = .pending
        self.name = name
        self.url = url
        self.type = type
        self.username = username
        self.password = password
    }
}

/// Wrapper for synced favorites
public struct SyncedFavorite: SyncableItem {
    public let id: UUID
    public var lastModified: Date
    public var syncStatus: SyncStatus

    public var channelId: UUID
    public var channelName: String
    public var addedAt: Date

    public init(id: UUID = UUID(), channelId: UUID, channelName: String, addedAt: Date = Date()) {
        self.id = id
        self.lastModified = Date()
        self.syncStatus = .pending
        self.channelId = channelId
        self.channelName = channelName
        self.addedAt = addedAt
    }
}

/// Wrapper for synced watch history
public struct SyncedWatchHistory: SyncableItem {
    public let id: UUID
    public var lastModified: Date
    public var syncStatus: SyncStatus

    public var channelId: UUID
    public var channelName: String
    public var watchedAt: Date
    public var duration: TimeInterval
    public var position: TimeInterval

    public init(id: UUID = UUID(), channelId: UUID, channelName: String, watchedAt: Date = Date(), duration: TimeInterval = 0, position: TimeInterval = 0) {
        self.id = id
        self.lastModified = Date()
        self.syncStatus = .pending
        self.channelId = channelId
        self.channelName = channelName
        self.watchedAt = watchedAt
        self.duration = duration
        self.position = position
    }
}

/// Wrapper for synced settings
public struct SyncedSettings: SyncableItem {
    public let id: UUID
    public var lastModified: Date
    public var syncStatus: SyncStatus

    public var theme: String
    public var autoplay: Bool
    public var volume: Double
    public var quality: String
    public var subtitlesEnabled: Bool
    public var parentalControlsEnabled: Bool

    public init(id: UUID = UUID(), theme: String = "dark", autoplay: Bool = true, volume: Double = 0.7, quality: String = "auto", subtitlesEnabled: Bool = false, parentalControlsEnabled: Bool = false) {
        self.id = id
        self.lastModified = Date()
        self.syncStatus = .pending
        self.theme = theme
        self.autoplay = autoplay
        self.volume = volume
        self.quality = quality
        self.subtitlesEnabled = subtitlesEnabled
        self.parentalControlsEnabled = parentalControlsEnabled
    }
}
