import Foundation
import CloudKit

/// Service for syncing data via iCloud
@MainActor
public class iCloudSyncService: ObservableObject {
    @Published public var isEnabled: Bool = false
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncDate: Date?
    @Published public var syncError: String?
    @Published public var conflictCount: Int = 0

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private var syncTimer: Timer?

    public init() {
        self.container = CKContainer(identifier: "iCloud.com.aether.iptv")
        self.privateDatabase = container.privateCloudDatabase

        // Check iCloud availability
        Task {
            await checkiCloudStatus()
        }
    }

    // MARK: - iCloud Status

    public func checkiCloudStatus() async {
        do {
            let status = try await container.accountStatus()
            isEnabled = (status == .available)

            if isEnabled {
                startAutoSync()
            }
        } catch {
            syncError = "iCloud not available: \(error.localizedDescription)"
            isEnabled = false
        }
    }

    // MARK: - Auto Sync

    private func startAutoSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncAll()
            }
        }
    }

    public func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Sync All

    public func syncAll() async {
        guard isEnabled else { return }

        isSyncing = true
        syncError = nil

        do {
            try await syncPlaylists()
            try await syncFavorites()
            try await syncWatchHistory()
            try await syncSettings()

            lastSyncDate = Date()
            conflictCount = 0
        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    // MARK: - Sync Playlists

    public func syncPlaylists() async throws {
        let recordType = "Playlist"

        // Fetch remote playlists
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)

        var remotePlaylists: [SyncedPlaylist] = []
        for (recordID, result) in results.matchResults {
            if case .success(let record) = result {
                if let playlist = try? decodePlaylist(from: record) {
                    remotePlaylists.append(playlist)
                }
            }
        }

        // TODO: Merge with local playlists and resolve conflicts
        // For now, just upload local playlists
    }

    public func uploadPlaylist(_ playlist: SyncedPlaylist) async throws {
        let record = CKRecord(recordType: "Playlist", recordID: CKRecord.ID(recordName: playlist.id.uuidString))
        record["name"] = playlist.name
        record["url"] = playlist.url
        record["type"] = playlist.type.rawValue
        record["username"] = playlist.username
        record["password"] = playlist.password
        record["lastModified"] = playlist.lastModified

        _ = try await privateDatabase.save(record)
    }

    public func deletePlaylist(_ playlistId: UUID) async throws {
        let recordID = CKRecord.ID(recordName: playlistId.uuidString)
        _ = try await privateDatabase.deleteRecord(withID: recordID)
    }

    private func decodePlaylist(from record: CKRecord) throws -> SyncedPlaylist {
        guard let name = record["name"] as? String,
              let url = record["url"] as? String,
              let typeRaw = record["type"] as? String,
              let type = PlaylistType(rawValue: typeRaw),
              let lastModified = record["lastModified"] as? Date else {
            throw NSError(domain: "iCloudSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid playlist record"])
        }

        var playlist = SyncedPlaylist(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            name: name,
            url: url,
            type: type,
            username: record["username"] as? String,
            password: record["password"] as? String
        )
        playlist.lastModified = lastModified
        playlist.syncStatus = .synced

        return playlist
    }

    // MARK: - Sync Favorites

    public func syncFavorites() async throws {
        let recordType = "Favorite"

        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)

        var remoteFavorites: [SyncedFavorite] = []
        for (recordID, result) in results.matchResults {
            if case .success(let record) = result {
                if let favorite = try? decodeFavorite(from: record) {
                    remoteFavorites.append(favorite)
                }
            }
        }
    }

    public func uploadFavorite(_ favorite: SyncedFavorite) async throws {
        let record = CKRecord(recordType: "Favorite", recordID: CKRecord.ID(recordName: favorite.id.uuidString))
        record["channelId"] = favorite.channelId.uuidString
        record["channelName"] = favorite.channelName
        record["addedAt"] = favorite.addedAt
        record["lastModified"] = favorite.lastModified

        _ = try await privateDatabase.save(record)
    }

    public func deleteFavorite(_ favoriteId: UUID) async throws {
        let recordID = CKRecord.ID(recordName: favoriteId.uuidString)
        _ = try await privateDatabase.deleteRecord(withID: recordID)
    }

    private func decodeFavorite(from record: CKRecord) throws -> SyncedFavorite {
        guard let channelIdString = record["channelId"] as? String,
              let channelId = UUID(uuidString: channelIdString),
              let channelName = record["channelName"] as? String,
              let addedAt = record["addedAt"] as? Date,
              let lastModified = record["lastModified"] as? Date else {
            throw NSError(domain: "iCloudSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid favorite record"])
        }

        var favorite = SyncedFavorite(id: UUID(uuidString: record.recordID.recordName) ?? UUID(), channelId: channelId, channelName: channelName, addedAt: addedAt)
        favorite.lastModified = lastModified
        favorite.syncStatus = .synced

        return favorite
    }

    // MARK: - Sync Watch History

    public func syncWatchHistory() async throws {
        let recordType = "WatchHistory"

        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "watchedAt", ascending: false)]

        let results = try await privateDatabase.records(matching: query)

        var remoteHistory: [SyncedWatchHistory] = []
        for (recordID, result) in results.matchResults {
            if case .success(let record) = result {
                if let history = try? decodeWatchHistory(from: record) {
                    remoteHistory.append(history)
                }
            }
        }
    }

    public func uploadWatchHistory(_ history: SyncedWatchHistory) async throws {
        let record = CKRecord(recordType: "WatchHistory", recordID: CKRecord.ID(recordName: history.id.uuidString))
        record["channelId"] = history.channelId.uuidString
        record["channelName"] = history.channelName
        record["watchedAt"] = history.watchedAt
        record["duration"] = history.duration
        record["position"] = history.position
        record["lastModified"] = history.lastModified

        _ = try await privateDatabase.save(record)
    }

    private func decodeWatchHistory(from record: CKRecord) throws -> SyncedWatchHistory {
        guard let channelIdString = record["channelId"] as? String,
              let channelId = UUID(uuidString: channelIdString),
              let channelName = record["channelName"] as? String,
              let watchedAt = record["watchedAt"] as? Date,
              let duration = record["duration"] as? Double,
              let position = record["position"] as? Double,
              let lastModified = record["lastModified"] as? Date else {
            throw NSError(domain: "iCloudSync", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid watch history record"])
        }

        var history = SyncedWatchHistory(id: UUID(uuidString: record.recordID.recordName) ?? UUID(), channelId: channelId, channelName: channelName, watchedAt: watchedAt, duration: duration, position: position)
        history.lastModified = lastModified
        history.syncStatus = .synced

        return history
    }

    // MARK: - Sync Settings

    public func syncSettings() async throws {
        let recordType = "Settings"
        let recordID = CKRecord.ID(recordName: "user-settings")

        do {
            let record = try await privateDatabase.record(for: recordID)
            // Settings exist, fetch them
            _ = try decodeSettings(from: record)
        } catch {
            // Settings don't exist yet
        }
    }

    public func uploadSettings(_ settings: SyncedSettings) async throws {
        let record = CKRecord(recordType: "Settings", recordID: CKRecord.ID(recordName: "user-settings"))
        record["theme"] = settings.theme
        record["autoplay"] = settings.autoplay ? 1 : 0
        record["volume"] = settings.volume
        record["quality"] = settings.quality
        record["subtitlesEnabled"] = settings.subtitlesEnabled ? 1 : 0
        record["parentalControlsEnabled"] = settings.parentalControlsEnabled ? 1 : 0
        record["lastModified"] = settings.lastModified

        _ = try await privateDatabase.save(record)
    }

    private func decodeSettings(from record: CKRecord) throws -> SyncedSettings {
        guard let theme = record["theme"] as? String,
              let autoplay = record["autoplay"] as? Int,
              let volume = record["volume"] as? Double,
              let quality = record["quality"] as? String,
              let subtitlesEnabled = record["subtitlesEnabled"] as? Int,
              let parentalControlsEnabled = record["parentalControlsEnabled"] as? Int,
              let lastModified = record["lastModified"] as? Date else {
            throw NSError(domain: "iCloudSync", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid settings record"])
        }

        var settings = SyncedSettings(theme: theme, autoplay: autoplay == 1, volume: volume, quality: quality, subtitlesEnabled: subtitlesEnabled == 1, parentalControlsEnabled: parentalControlsEnabled == 1)
        settings.lastModified = lastModified
        settings.syncStatus = .synced

        return settings
    }

    // MARK: - Conflict Resolution

    public func resolveConflict<T: SyncableItem>(local: T, remote: T, strategy: ConflictResolutionStrategy) -> T {
        switch strategy {
        case .useLocal:
            return local
        case .useRemote:
            return remote
        case .useNewest:
            return local.lastModified > remote.lastModified ? local : remote
        case .useOldest:
            return local.lastModified < remote.lastModified ? local : remote
        }
    }
}

/// Conflict resolution strategies
public enum ConflictResolutionStrategy {
    case useLocal
    case useRemote
    case useNewest
    case useOldest
}
