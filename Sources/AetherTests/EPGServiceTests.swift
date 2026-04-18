import XCTest
@testable import AetherCore

/// Tests for EPGService data parsing and caching.
final class EPGServiceTests: XCTestCase {

    func testEPGEntryCreation() {
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let entry = EPGEntry(
            channelID: "test-channel",
            title: "Test Program",
            start: start,
            end: end,
            description: "Test description"
        )

        XCTAssertEqual(entry.channelID, "test-channel")
        XCTAssertEqual(entry.title, "Test Program")
        XCTAssertEqual(entry.start, start)
        XCTAssertEqual(entry.end, end)
        XCTAssertEqual(entry.description, "Test description")
    }

    func testEPGEntryProgress() {
        let now = Date()
        let start = now.addingTimeInterval(-1800) // 30 min ago
        let end = now.addingTimeInterval(1800)    // 30 min from now
        let entry = EPGEntry(
            channelID: "test",
            title: "Test",
            start: start,
            end: end,
            description: nil
        )

        let progress = entry.progress()
        XCTAssertGreaterThan(progress, 0.4)
        XCTAssertLessThan(progress, 0.6)
    }

    func testEPGEntryProgressBeforeStart() {
        let now = Date()
        let start = now.addingTimeInterval(3600)  // 1 hour from now
        let end = start.addingTimeInterval(3600)
        let entry = EPGEntry(
            channelID: "test",
            title: "Test",
            start: start,
            end: end,
            description: nil
        )

        XCTAssertEqual(entry.progress(), 0)
    }

    func testEPGEntryProgressAfterEnd() {
        let now = Date()
        let start = now.addingTimeInterval(-7200) // 2 hours ago
        let end = now.addingTimeInterval(-3600)   // 1 hour ago
        let entry = EPGEntry(
            channelID: "test",
            title: "Test",
            start: start,
            end: end,
            description: nil
        )

        XCTAssertEqual(entry.progress(), 1)
    }

    @MainActor
    func testEPGServiceInitialization() {
        let service = EPGService()
        XCTAssertNotNil(service)
    }

    @MainActor
    func testEPGStoreInitialization() {
        let store = EPGStore()
        XCTAssertNotNil(store)
        XCTAssertNil(store.currentEPGURL)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.nowPlayingCache.isEmpty)
    }
}
