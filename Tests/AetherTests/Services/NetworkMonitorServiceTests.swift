import XCTest
@testable import AetherCore

@MainActor
final class NetworkMonitorServiceTests: XCTestCase {

    func testNetworkMonitorInitialization() {
        let service = NetworkMonitorService()

        XCTAssertNotNil(service)
    }

    func testOfflineQueueInitialization() {
        let networkMonitor = NetworkMonitorService()
        let offlineQueue = OfflineQueueService(networkMonitor: networkMonitor)

        XCTAssertNotNil(offlineQueue)
        XCTAssertTrue(offlineQueue.queuedOperations.isEmpty)
    }

    func testQueueOperation() {
        let networkMonitor = NetworkMonitorService()
        let offlineQueue = OfflineQueueService(networkMonitor: networkMonitor)

        let operation = OfflineQueueService.QueuedOperation(
            id: UUID(),
            type: .playlistRefresh,
            timestamp: Date(),
            retryCount: 0,
            data: ["url": "http://example.com/playlist.m3u"]
        )

        offlineQueue.queueOperation(operation)

        XCTAssertEqual(offlineQueue.queuedOperations.count, 1)
        XCTAssertEqual(offlineQueue.queuedOperations.first?.type, .playlistRefresh)
    }

    func testRemoveOperation() {
        let networkMonitor = NetworkMonitorService()
        let offlineQueue = OfflineQueueService(networkMonitor: networkMonitor)

        let operation = OfflineQueueService.QueuedOperation(
            id: UUID(),
            type: .playlistRefresh,
            timestamp: Date(),
            retryCount: 0,
            data: ["url": "http://example.com/playlist.m3u"]
        )

        offlineQueue.queueOperation(operation)
        XCTAssertEqual(offlineQueue.queuedOperations.count, 1)

        offlineQueue.removeOperation(operation.id)
        XCTAssertEqual(offlineQueue.queuedOperations.count, 0)
    }

    func testClearQueue() {
        let networkMonitor = NetworkMonitorService()
        let offlineQueue = OfflineQueueService(networkMonitor: networkMonitor)

        let operation1 = OfflineQueueService.QueuedOperation(
            id: UUID(),
            type: .playlistRefresh,
            timestamp: Date(),
            retryCount: 0,
            data: ["url": "http://example.com/playlist1.m3u"]
        )

        let operation2 = OfflineQueueService.QueuedOperation(
            id: UUID(),
            type: .epgUpdate,
            timestamp: Date(),
            retryCount: 0,
            data: ["url": "http://example.com/epg.xml"]
        )

        offlineQueue.queueOperation(operation1)
        offlineQueue.queueOperation(operation2)
        XCTAssertEqual(offlineQueue.queuedOperations.count, 2)

        offlineQueue.clearQueue()
        XCTAssertEqual(offlineQueue.queuedOperations.count, 0)
    }
}
