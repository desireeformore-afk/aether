import Foundation
import Observation
import CloudKit

public enum CloudKitError: Error, LocalizedError {
    case accountNotAvailable
    case accountCheckFailed(Error)
    case setupFailed(Error)
    case syncFailed(Error)
    case invalidRecord

    public var errorDescription: String? {
        switch self {
        case .accountNotAvailable: return "iCloud account not available"
        case .accountCheckFailed(let e): return "Account check failed: \(e.localizedDescription)"
        case .setupFailed(let e): return "CloudKit setup failed: \(e.localizedDescription)"
        case .syncFailed(let e): return "Sync failed: \(e.localizedDescription)"
        case .invalidRecord: return "Invalid CloudKit record"
        }
    }
}

@MainActor
@Observable
public final class CloudKitManager {
    public static let shared = CloudKitManager()
    
    public private(set) var isSyncing = false
    public private(set) var lastSyncDate: Date?
    public private(set) var syncError: Error?
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    
    private init() {
        self.container = CKContainer(identifier: "iCloud.com.aether.app")
        self.privateDatabase = container.privateCloudDatabase
    }
    
    // MARK: - Playlist Sync
    
    public func syncPlaylists(_ playlists: [Playlist]) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let query = CKQuery(recordType: "Playlist", predicate: NSPredicate(value: true))
            let results = try await privateDatabase.records(matching: query)
            
            var existingRecords: [String: CKRecord] = [:]
            for (_, result) in results.matchResults {
                if case .success(let record) = result {
                    if let playlistID = record["playlistID"] as? String {
                        existingRecords[playlistID] = record
                    }
                }
            }
            
            for playlist in playlists {
                let record: CKRecord
                if let existing = existingRecords[playlist.id.uuidString] {
                    record = existing
                } else {
                    let recordID = CKRecord.ID(recordName: playlist.id.uuidString)
                    record = CKRecord(recordType: "Playlist", recordID: recordID)
                }
                
                record["playlistID"] = playlist.id.uuidString
                record["name"] = playlist.name
                record["url"] = playlist.url.absoluteString
                record["channelCount"] = playlist.channels.count
                record["lastModified"] = Date()
                
                try await privateDatabase.save(record)
            }
            
            lastSyncDate = Date()
            syncError = nil
        } catch {
            syncError = error
            throw error
        }
    }
    
    public func fetchPlaylists() async throws -> [PlaylistMetadata] {
        let query = CKQuery(recordType: "Playlist", predicate: NSPredicate(value: true))
        let results = try await privateDatabase.records(matching: query)
        
        var playlists: [PlaylistMetadata] = []
        for (_, result) in results.matchResults {
            if case .success(let record) = result,
               let playlistID = record["playlistID"] as? String,
               let name = record["name"] as? String,
               let urlString = record["url"] as? String,
               let url = URL(string: urlString),
               let channelCount = record["channelCount"] as? Int,
               let lastModified = record["lastModified"] as? Date {
                
                playlists.append(PlaylistMetadata(
                    id: UUID(uuidString: playlistID) ?? UUID(),
                    name: name,
                    url: url,
                    channelCount: channelCount,
                    lastModified: lastModified
                ))
            }
        }
        
        return playlists
    }
    
    // MARK: - Favorites Sync
    
    public func syncFavorites(_ channelIDs: [String]) async throws {
        let recordID = CKRecord.ID(recordName: "UserFavorites")
        let record: CKRecord
        
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: "Favorites", recordID: recordID)
        }
        
        record["channelIDs"] = channelIDs
        record["lastModified"] = Date()
        
        try await privateDatabase.save(record)
        lastSyncDate = Date()
    }
    
    public func fetchFavorites() async throws -> [String] {
        let recordID = CKRecord.ID(recordName: "UserFavorites")
        
        do {
            let record = try await privateDatabase.record(for: recordID)
            return record["channelIDs"] as? [String] ?? []
        } catch {
            return []
        }
    }
    
    // MARK: - Settings Sync
    
    public func syncSettings(_ settings: [String: Any]) async throws {
        let recordID = CKRecord.ID(recordName: "UserSettings")
        let record: CKRecord
        
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: "Settings", recordID: recordID)
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: settings)
        record["settingsJSON"] = String(data: jsonData, encoding: .utf8)
        record["lastModified"] = Date()
        
        try await privateDatabase.save(record)
        lastSyncDate = Date()
    }
    
    public func fetchSettings() async throws -> [String: Any] {
        let recordID = CKRecord.ID(recordName: "UserSettings")
        
        do {
            let record = try await privateDatabase.record(for: recordID)
            if let jsonString = record["settingsJSON"] as? String,
               let jsonData = jsonString.data(using: .utf8),
               let settings = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                return settings
            }
        } catch {}
        
        return [:]
    }
}

public struct PlaylistMetadata: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let channelCount: Int
    public let lastModified: Date
}

public struct WatchHistoryEntry: Identifiable, Codable {
    public let id: UUID
    public let channelID: String
    public let channelName: String
    public let watchedAt: Date
    public let duration: TimeInterval
}
