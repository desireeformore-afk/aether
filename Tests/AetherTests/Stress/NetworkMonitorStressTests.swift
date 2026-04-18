import XCTest
@testable import AetherCore

@MainActor
final class NetworkMonitorStressTests: XCTestCase {

    func testMassOperationQueuing() {
        let networkMonitor = NetworkMonitorService()
        let offlineQueue = OfflineQueueService(networkMonitor: networkMonitor)

        // Queue many operations
        for i in 1...1000 {
            let operation = OfflineQueueService.QueuedOperation(
                id: UUID(),
                type: .playlistRefresh,
                timestamp: Date(),
                retryCount: 0,
                data: ["url": "http://example.com/playlist\(i).m3u"]
            )
            offlineQueue.queueOperation(operation)
        }

        XCTAssertEqual(offlineQueue.queuedOperations.count, 1000)
    }

    func testRapidQueueClearance() {
        let networkMonitor = NetworkMonitorService()
        let offlineQueue = OfflineQueueService(networkMonitor: networkMonitor)

        // Queue and clear many times
        for i in 1...100 {
            // Queue operations
            for j in 1...10 {
                let operation = OfflineQueueService.QueuedOperation(
                    id: UUID(),
                    type: .playlistRefresh,
                    timestamp: Date(),
                    retryCount: 0,
                    data: ["url": "http://example.com/playlist\(i)-\(j).m3u"]
                )
                offlineQueue.queueOperation(operation)
            }

            // Clear queue
            offlineQueue.clearQueue()
        }

        XCTAssertEqual(offlineQueue.queuedOperations.count, 0)
    }

    func testConcurrentOperationRemoval() {
        let networkMonitor = NetworkMonitorService()
        let offlineQueue = OfflineQueueService(networkMonitor: networkMonitor)

        // Queue many operations
        var operationIds: [UUID] = []
        for i in 1...500 {
            let operation = OfflineQueueService.QueuedOperation(
                id: UUID(),
                type: .playlistRefresh,
                timestamp: Date(),
                retryCount: 0,
                data: ["url": "http://example.com/playlist\(i).m3u"]
            )
            operationIds.append(operation.id)
            offlineQueue.queueOperation(operation)
        }

        // Remove all operations
        for id in operationIds {
            offlineQueue.removeOperation(id)
        }

        XCTAssertEqual(offlineQueue.queuedOperations.count, 0)
    }

    func testMixedOperationTypes() {
        let networkMonitor = NetworkMonitorService()
        let offlineQueue = OfflineQueueService(networkMonitor: networkMonitor)

        let types: [OfflineQueueService.OperationType] = [
            .playlistRefresh,
            .epgUpdate,
            .favoriteSync
        ]

        // Queue many operations of different types
        for i in 1...300 {
            let operation = OfflineQueueService.QueuedOperation(
                id: UUID(),
                type: types[i % types.count],
                timestamp: Date(),
                retryCount: 0,
                data: ["index": "\(i)"]
            )
            offlineQueue.queueOperation(operation)
        }

        XCTAssertEqual(offlineQueue.queuedOperations.count, 300)
    }

    func testRetryCountStress() {
        let networkMonitor = NetworkMonitorService()
        let offlineQueue = OfflineQueueService(networkMonitor: networkMonitor)

        // Queue operations with various retry counts
        for i in 1...100 {
            let operation = OfflineQueueService.QueuedOperation(
                id: UUID(),
                type: .playlistRefresh,
                timestamp: Date(),
                retryCount: i % 10,
                data: ["url": "http://example.com/playlist\(i).m3u"]
            )
            offlineQueue.queueOperation(operation)
        }

        XCTAssertEqual(offlineQueue.queuedOperations.count, 100)
    }
}
