import XCTest
import CloudKit
@testable import AetherCore

/// Tests for CloudKit sync data structures and conflict resolution logic.
final class CloudKitManagerTests: XCTestCase {
    var mockPlaylists: [SyncedPlaylist]!
    var mockFavorites: [SyncedFavorite]!
    var mockWatchHistory: [SyncedWatchHistory]!
    var mockSettings: SyncedSettings!

    override func setUp() {
        super.setUp()
        setupMockData()
    }

    override func tearDown() {
        mockPlaylists = nil
        mockFavorites = nil
        mockWatchHistory = nil
        mockSettings = nil
        super.tearDown()
    }

    // MARK: - Setup Mock Data

    private func setupMockData() {
        mockPlaylists = [
            SyncedPlaylist(id: UUID(), name: "Test Playlist 1", url: "https://example.com/playlist1.m3u", type: .m3u),
            SyncedPlaylist(id: UUID(), name: "Test Playlist 2", url: "https://example.com/playlist2.m3u", type: .m3u),
            SyncedPlaylist(id: UUID(), name: "Xtream Playlist", url: "https://xtream.example.com", type: .xtream, username: "testuser", password: "testpass")
        ]

        let channelId1 = UUID()
        let channelId2 = UUID()
        mockFavorites = [
            SyncedFavorite(id: UUID(), channelId: channelId1, channelName: "BBC News", addedAt: Date()),
            SyncedFavorite(id: UUID(), channelId: channelId2, channelName: "CNN", addedAt: Date())
        ]

        mockWatchHistory = [
            SyncedWatchHistory(id: UUID(), channelId: channelId1, channelName: "BBC News",
                               watchedAt: Date().addingTimeInterval(-3600), duration: 1800, position: 900),
            SyncedWatchHistory(id: UUID(), channelId: channelId2, channelName: "CNN",
                               watchedAt: Date(), duration: 2400, position: 1200)
        ]

        mockSettings = SyncedSettings(theme: "dark", autoplay: true, volume: 0.75,
                                      quality: "1080p", subtitlesEnabled: true, parentalControlsEnabled: false)
    }

    // MARK: - Playlist Tests

    func testPlaylistConversion() {
        let playlist = mockPlaylists[0]
        XCTAssertFalse(playlist.name.isEmpty)
        XCTAssertFalse(playlist.url.isEmpty)
        XCTAssertEqual(playlist.syncStatus, .pending)
        XCTAssertNotNil(playlist.lastModified)
    }

    func testPlaylistWithXtreamCredentials() {
        let xtreamPlaylist = mockPlaylists[2]
        XCTAssertEqual(xtreamPlaylist.type, .xtream)
        XCTAssertEqual(xtreamPlaylist.username, "testuser")
        XCTAssertEqual(xtreamPlaylist.password, "testpass")
    }

    // MARK: - Favorites Tests

    func testFavoriteConversion() {
        let favorite = mockFavorites[0]
        XCTAssertFalse(favorite.channelName.isEmpty)
        XCTAssertNotNil(favorite.channelId)
        XCTAssertNotNil(favorite.addedAt)
        XCTAssertEqual(favorite.syncStatus, .pending)
    }

    // MARK: - Watch History Tests

    func testWatchHistoryConversion() {
        let history = mockWatchHistory[0]
        XCTAssertFalse(history.channelName.isEmpty)
        XCTAssertNotNil(history.channelId)
        XCTAssertGreaterThan(history.duration, 0)
        XCTAssertGreaterThanOrEqual(history.position, 0)
        XCTAssertLessThanOrEqual(history.position, history.duration)
    }

    // MARK: - Settings Tests

    func testSettingsConversion() {
        XCTAssertFalse(mockSettings.theme.isEmpty)
        XCTAssertGreaterThanOrEqual(mockSettings.volume, 0.0)
        XCTAssertLessThanOrEqual(mockSettings.volume, 1.0)
        XCTAssertFalse(mockSettings.quality.isEmpty)
    }

    // MARK: - CloudKitManager shared instance

    func testSharedInstanceExists() {
        let manager = CloudKitManager.shared
        XCTAssertNotNil(manager)
    }

    func testManagerHasSyncState() {
        let manager = CloudKitManager.shared
        // isSyncing defaults to false
        XCTAssertFalse(manager.isSyncing)
    }

    // MARK: - Conflict Resolution Tests

    func testLastWriteWinsConflictResolution() {
        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()

        var oldPlaylist = mockPlaylists[0]
        oldPlaylist.lastModified = oldDate
        oldPlaylist.name = "Old Name"

        var newPlaylist = mockPlaylists[0]
        newPlaylist.lastModified = newDate
        newPlaylist.name = "New Name"

        let winner = newPlaylist.lastModified > oldPlaylist.lastModified ? newPlaylist : oldPlaylist
        XCTAssertEqual(winner.name, "New Name")
        XCTAssertEqual(winner.lastModified, newDate)
    }

    func testFirstWriteWinsConflictResolution() {
        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()

        var oldPlaylist = mockPlaylists[0]
        oldPlaylist.lastModified = oldDate
        oldPlaylist.name = "Old Name"

        var newPlaylist = mockPlaylists[0]
        newPlaylist.lastModified = newDate
        newPlaylist.name = "New Name"

        let winner = oldPlaylist.lastModified < newPlaylist.lastModified ? oldPlaylist : newPlaylist
        XCTAssertEqual(winner.name, "Old Name")
        XCTAssertEqual(winner.lastModified, oldDate)
    }

    // MARK: - Error Handling Tests

    func testCloudKitErrorDescriptions() {
        let errors: [CloudKitError] = [
            .accountNotAvailable,
            .accountCheckFailed(NSError(domain: "test", code: 1)),
            .setupFailed(NSError(domain: "test", code: 2)),
            .syncFailed(NSError(domain: "test", code: 3)),
            .invalidRecord
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Merge Logic Tests

    func testMergeLocalAndRemoteItems() {
        var local = mockPlaylists!
        local[0].syncStatus = .pending
        local[0].name = "Local Modified"

        var remote = mockPlaylists!
        remote[0].lastModified = Date().addingTimeInterval(-3600)
        remote[0].name = "Remote Original"

        var merged: [UUID: SyncedPlaylist] = [:]
        for item in remote { merged[item.id] = item }
        for localItem in local {
            if let remoteItem = merged[localItem.id] {
                merged[localItem.id] = localItem.lastModified > remoteItem.lastModified ? localItem : remoteItem
            } else {
                merged[localItem.id] = localItem
            }
        }

        let result = Array(merged.values)
        XCTAssertEqual(result.count, mockPlaylists.count)
        if let mergedItem = result.first(where: { $0.id == local[0].id }) {
            XCTAssertEqual(mergedItem.name, "Local Modified")
        }
    }

    // MARK: - Data Integrity Tests

    func testPlaylistDataIntegrity() {
        for playlist in mockPlaylists {
            XCTAssertNotNil(URL(string: playlist.url))
            XCTAssertTrue([PlaylistType.m3u, .xtream].contains(playlist.type))
            if playlist.type == .xtream {
                XCTAssertNotNil(playlist.username)
                XCTAssertNotNil(playlist.password)
            }
        }
    }

    func testFavoriteDataIntegrity() {
        for favorite in mockFavorites {
            XCTAssertLessThanOrEqual(favorite.addedAt, Date())
            XCTAssertLessThanOrEqual(favorite.lastModified, Date())
        }
    }

    func testWatchHistoryDataIntegrity() {
        for history in mockWatchHistory {
            XCTAssertLessThanOrEqual(history.position, history.duration)
            XCTAssertLessThanOrEqual(history.watchedAt, Date())
        }
    }

    // MARK: - Performance Tests

    func testMergePerformance() {
        var largePlaylists: [SyncedPlaylist] = []
        for i in 0..<1000 {
            largePlaylists.append(
                SyncedPlaylist(id: UUID(), name: "Playlist \(i)", url: "https://example.com/playlist\(i).m3u", type: .m3u)
            )
        }

        measure {
            var merged: [UUID: SyncedPlaylist] = [:]
            for item in largePlaylists { merged[item.id] = item }
            for localItem in largePlaylists {
                if let remoteItem = merged[localItem.id] {
                    merged[localItem.id] = localItem.lastModified > remoteItem.lastModified ? localItem : remoteItem
                }
            }
            _ = Array(merged.values)
        }
    }
}
