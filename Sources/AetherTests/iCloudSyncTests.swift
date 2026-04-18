import XCTest
@testable import AetherCore

final class iCloudSyncTests: XCTestCase {
    var syncService: iCloudSyncService!

    override func setUp() async throws {
        syncService = await iCloudSyncService()
    }

    func testSyncablePlaylist() {
        let playlist = SyncedPlaylist(
            name: "Test Playlist",
            url: "https://example.com/playlist.m3u",
            type: .m3u
        )

        XCTAssertEqual(playlist.name, "Test Playlist")
        XCTAssertEqual(playlist.syncStatus, .pending)
        XCTAssertNotNil(playlist.id)
    }

    func testSyncableFavorite() {
        let channelId = UUID()
        let favorite = SyncedFavorite(
            channelId: channelId,
            channelName: "Test Channel"
        )

        XCTAssertEqual(favorite.channelId, channelId)
        XCTAssertEqual(favorite.channelName, "Test Channel")
        XCTAssertEqual(favorite.syncStatus, .pending)
    }

    func testSyncedWatchHistory() {
        let channelId = UUID()
        let history = SyncedWatchHistory(
            channelId: channelId,
            channelName: "Test Channel",
            duration: 3600,
            position: 1800
        )

        XCTAssertEqual(history.channelId, channelId)
        XCTAssertEqual(history.duration, 3600)
        XCTAssertEqual(history.position, 1800)
        XCTAssertEqual(history.syncStatus, .pending)
    }

    func testSyncedSettings() {
        let settings = SyncedSettings(
            theme: "dark",
            autoplay: true,
            volume: 0.8
        )

        XCTAssertEqual(settings.theme, "dark")
        XCTAssertEqual(settings.autoplay, true)
        XCTAssertEqual(settings.volume, 0.8)
        XCTAssertEqual(settings.syncStatus, .pending)
    }

    func testSyncStatusEnum() {
        XCTAssertEqual(SyncStatus.synced.rawValue, "synced")
        XCTAssertEqual(SyncStatus.pending.rawValue, "pending")
        XCTAssertEqual(SyncStatus.conflict.rawValue, "conflict")
        XCTAssertEqual(SyncStatus.error.rawValue, "error")
    }

    func testPlaylistCodable() throws {
        let playlist = SyncedPlaylist(
            name: "Test",
            url: "https://example.com/test.m3u",
            type: .m3u,
            username: "user",
            password: "pass"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(playlist)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncedPlaylist.self, from: data)

        XCTAssertEqual(decoded.name, playlist.name)
        XCTAssertEqual(decoded.url, playlist.url)
        XCTAssertEqual(decoded.username, playlist.username)
    }

    func testFavoriteCodable() throws {
        let favorite = SyncedFavorite(
            channelId: UUID(),
            channelName: "Test Channel"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(favorite)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncedFavorite.self, from: data)

        XCTAssertEqual(decoded.channelId, favorite.channelId)
        XCTAssertEqual(decoded.channelName, favorite.channelName)
    }

    func testWatchHistoryCodable() throws {
        let history = SyncedWatchHistory(
            channelId: UUID(),
            channelName: "Test Channel",
            duration: 3600,
            position: 1800
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(history)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncedWatchHistory.self, from: data)

        XCTAssertEqual(decoded.channelId, history.channelId)
        XCTAssertEqual(decoded.duration, history.duration)
        XCTAssertEqual(decoded.position, history.position)
    }

    func testSettingsCodable() throws {
        let settings = SyncedSettings(
            theme: "dark",
            autoplay: true,
            volume: 0.8
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncedSettings.self, from: data)

        XCTAssertEqual(decoded.theme, settings.theme)
        XCTAssertEqual(decoded.autoplay, settings.autoplay)
        XCTAssertEqual(decoded.volume, settings.volume)
    }
}
