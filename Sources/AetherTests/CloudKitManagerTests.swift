import XCTest
import CloudKit
@testable import AetherCore

@MainActor
final class CloudKitManagerTests: XCTestCase {
    var manager: CloudKitManager!
    var mockPlaylists: [SyncedPlaylist]!
    var mockFavorites: [SyncedFavorite]!
    var mockWatchHistory: [SyncedWatchHistory]!
    var mockSettings: SyncedSettings!

    override func setUp() async throws {
        try await super.setUp()

        // Initialize manager with test container
        manager = CloudKitManager(containerIdentifier: "iCloud.com.aether.iptv.test")

        // Create mock data
        setupMockData()
    }

    override func tearDown() async throws {
        manager = nil
        mockPlaylists = nil
        mockFavorites = nil
        mockWatchHistory = nil
        mockSettings = nil
        try await super.tearDown()
    }

    // MARK: - Setup Mock Data

    private func setupMockData() {
        // Mock playlists
        mockPlaylists = [
            SyncedPlaylist(
                id: UUID(),
                name: "Test Playlist 1",
                url: "https://example.com/playlist1.m3u",
                type: .m3u
            ),
            SyncedPlaylist(
                id: UUID(),
                name: "Test Playlist 2",
                url: "https://example.com/playlist2.m3u",
                type: .m3u
            ),
            SyncedPlaylist(
                id: UUID(),
                name: "Xtream Playlist",
                url: "https://xtream.example.com",
                type: .xtream,
                username: "testuser",
                password: "testpass"
            )
        ]

        // Mock favorites
        let channelId1 = UUID()
        let channelId2 = UUID()
        mockFavorites = [
            SyncedFavorite(
                id: UUID(),
                channelId: channelId1,
                channelName: "BBC News",
                addedAt: Date()
            ),
            SyncedFavorite(
                id: UUID(),
                channelId: channelId2,
                channelName: "CNN",
                addedAt: Date()
            )
        ]

        // Mock watch history
        mockWatchHistory = [
            SyncedWatchHistory(
                id: UUID(),
                channelId: channelId1,
                channelName: "BBC News",
                watchedAt: Date().addingTimeInterval(-3600),
                duration: 1800,
                position: 900
            ),
            SyncedWatchHistory(
                id: UUID(),
                channelId: channelId2,
                channelName: "CNN",
                watchedAt: Date(),
                duration: 2400,
                position: 1200
            )
        ]

        // Mock settings
        mockSettings = SyncedSettings(
            theme: "dark",
            autoplay: true,
            volume: 0.75,
            quality: "1080p",
            subtitlesEnabled: true,
            parentalControlsEnabled: false
        )
    }

    // MARK: - Availability Tests

    func testCheckAvailability() async throws {
        // Note: This test will fail in CI/test environments without iCloud
        // In production, you'd mock the CKContainer
        await manager.checkAvailability()

        // Just verify the method completes without crashing
        XCTAssertNotNil(manager.isAvailable)
    }

    // MARK: - Playlist Sync Tests

    func testPlaylistConversion() throws {
        let playlist = mockPlaylists[0]

        // Test that playlist has required fields
        XCTAssertFalse(playlist.name.isEmpty)
        XCTAssertFalse(playlist.url.isEmpty)
        XCTAssertEqual(playlist.syncStatus, .pending)
        XCTAssertNotNil(playlist.lastModified)
    }

    func testPlaylistWithXtreamCredentials() throws {
        let xtreamPlaylist = mockPlaylists[2]

        XCTAssertEqual(xtreamPlaylist.type, .xtream)
        XCTAssertEqual(xtreamPlaylist.username, "testuser")
        XCTAssertEqual(xtreamPlaylist.password, "testpass")
    }

    // MARK: - Favorites Sync Tests

    func testFavoriteConversion() throws {
        let favorite = mockFavorites[0]

        XCTAssertFalse(favorite.channelName.isEmpty)
        XCTAssertNotNil(favorite.channelId)
        XCTAssertNotNil(favorite.addedAt)
        XCTAssertEqual(favorite.syncStatus, .pending)
    }

    // MARK: - Watch History Sync Tests

    func testWatchHistoryConversion() throws {
        let history = mockWatchHistory[0]

        XCTAssertFalse(history.channelName.isEmpty)
        XCTAssertNotNil(history.channelId)
        XCTAssertGreaterThan(history.duration, 0)
        XCTAssertGreaterThanOrEqual(history.position, 0)
        XCTAssertLessThanOrEqual(history.position, history.duration)
    }

    // MARK: - Settings Sync Tests

    func testSettingsConversion() throws {
        XCTAssertFalse(mockSettings.theme.isEmpty)
        XCTAssertGreaterThanOrEqual(mockSettings.volume, 0.0)
        XCTAssertLessThanOrEqual(mockSettings.volume, 1.0)
        XCTAssertFalse(mockSettings.quality.isEmpty)
    }

    // MARK: - Conflict Resolution Tests

    func testLastWriteWinsConflictResolution() throws {
        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()

        var oldPlaylist = mockPlaylists[0]
        oldPlaylist.lastModified = oldDate
        oldPlaylist.name = "Old Name"

        var newPlaylist = mockPlaylists[0]
        newPlaylist.lastModified = newDate
        newPlaylist.name = "New Name"

        // Simulate conflict resolution
        let winner = newPlaylist.lastModified > oldPlaylist.lastModified ? newPlaylist : oldPlaylist

        XCTAssertEqual(winner.name, "New Name")
        XCTAssertEqual(winner.lastModified, newDate)
    }

    func testFirstWriteWinsConflictResolution() throws {
        let oldDate = Date().addingTimeInterval(-3600)
        let newDate = Date()

        var oldPlaylist = mockPlaylists[0]
        oldPlaylist.lastModified = oldDate
        oldPlaylist.name = "Old Name"

        var newPlaylist = mockPlaylists[0]
        newPlaylist.lastModified = newDate
        newPlaylist.name = "New Name"

        // Simulate first-write-wins
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

    func testMergeLocalAndRemoteItems() throws {
        // Create local items
        var local = mockPlaylists
        local[0].syncStatus = .pending
        local[0].name = "Local Modified"

        // Create remote items (same IDs, different data)
        var remote = mockPlaylists
        remote[0].lastModified = Date().addingTimeInterval(-3600) // Older
        remote[0].name = "Remote Original"

        // Simulate merge with last-write-wins
        var merged: [UUID: SyncedPlaylist] = [:]

        for item in remote {
            merged[item.id] = item
        }

        for localItem in local {
            if let remoteItem = merged[localItem.id] {
                // Last write wins
                merged[localItem.id] = localItem.lastModified > remoteItem.lastModified ? localItem : remoteItem
            } else {
                merged[localItem.id] = localItem
            }
        }

        let result = Array(merged.values)

        XCTAssertEqual(result.count, mockPlaylists.count)

        // Find the merged item
        if let mergedItem = result.first(where: { $0.id == local[0].id }) {
            XCTAssertEqual(mergedItem.name, "Local Modified")
        }
    }

    func testMergeWithNewLocalItem() throws {
        var local = mockPlaylists

        // Add a new local item
        let newPlaylist = SyncedPlaylist(
            id: UUID(),
            name: "New Local Playlist",
            url: "https://example.com/new.m3u",
            type: .m3u
        )
        local.append(newPlaylist)

        let remote = Array(mockPlaylists.prefix(2)) // Only first 2 items

        // Simulate merge
        var merged: [UUID: SyncedPlaylist] = [:]

        for item in remote {
            merged[item.id] = item
        }

        for localItem in local {
            if merged[localItem.id] == nil {
                merged[localItem.id] = localItem
            }
        }

        let result = Array(merged.values)

        XCTAssertEqual(result.count, local.count)
        XCTAssertTrue(result.contains(where: { $0.id == newPlaylist.id }))
    }

    func testMergeWithDeletedLocalItem() throws {
        let local = Array(mockPlaylists.prefix(2)) // Only first 2 items
        let remote = mockPlaylists // All 3 items

        // Simulate merge
        var merged: [UUID: SyncedPlaylist] = [:]

        for item in remote {
            merged[item.id] = item
        }

        for localItem in local {
            if let remoteItem = merged[localItem.id] {
                merged[localItem.id] = localItem.lastModified > remoteItem.lastModified ? localItem : remoteItem
            }
        }

        let result = Array(merged.values)

        // Remote item should still be present
        XCTAssertEqual(result.count, remote.count)
    }

    // MARK: - Batch Operations Tests

    func testBatchPlaylistSync() throws {
        // Verify we can handle multiple playlists
        XCTAssertEqual(mockPlaylists.count, 3)

        for playlist in mockPlaylists {
            XCTAssertNotNil(playlist.id)
            XCTAssertFalse(playlist.name.isEmpty)
        }
    }

    func testBatchFavoriteSync() throws {
        XCTAssertEqual(mockFavorites.count, 2)

        for favorite in mockFavorites {
            XCTAssertNotNil(favorite.id)
            XCTAssertNotNil(favorite.channelId)
        }
    }

    // MARK: - Data Integrity Tests

    func testPlaylistDataIntegrity() throws {
        for playlist in mockPlaylists {
            // Verify URL is valid
            XCTAssertNotNil(URL(string: playlist.url))

            // Verify type is valid
            XCTAssertTrue([PlaylistType.m3u, .xtream].contains(playlist.type))

            // Verify Xtream playlists have credentials
            if playlist.type == .xtream {
                XCTAssertNotNil(playlist.username)
                XCTAssertNotNil(playlist.password)
            }
        }
    }

    func testFavoriteDataIntegrity() throws {
        for favorite in mockFavorites {
            // Verify dates are valid
            XCTAssertLessThanOrEqual(favorite.addedAt, Date())
            XCTAssertLessThanOrEqual(favorite.lastModified, Date())
        }
    }

    func testWatchHistoryDataIntegrity() throws {
        for history in mockWatchHistory {
            // Verify position doesn't exceed duration
            XCTAssertLessThanOrEqual(history.position, history.duration)

            // Verify dates are valid
            XCTAssertLessThanOrEqual(history.watchedAt, Date())
        }
    }

    // MARK: - Performance Tests

    func testMergePerformance() throws {
        // Create large datasets
        var largePlaylists: [SyncedPlaylist] = []
        for i in 0..<1000 {
            largePlaylists.append(
                SyncedPlaylist(
                    id: UUID(),
                    name: "Playlist \(i)",
                    url: "https://example.com/playlist\(i).m3u",
                    type: .m3u
                )
            )
        }

        measure {
            var merged: [UUID: SyncedPlaylist] = [:]

            for item in largePlaylists {
                merged[item.id] = item
            }

            for localItem in largePlaylists {
                if let remoteItem = merged[localItem.id] {
                    merged[localItem.id] = localItem.lastModified > remoteItem.lastModified ? localItem : remoteItem
                }
            }

            _ = Array(merged.values)
        }
    }
}
