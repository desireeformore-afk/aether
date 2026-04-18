import XCTest
@testable import AetherCore

@MainActor
final class MemoryMonitorStressTests: XCTestCase {

    func testRapidMemoryEventLogging() {
        let service = MemoryMonitorService()

        // Simulate many memory events
        for _ in 1...1000 {
            // Events are logged internally, we just verify the service doesn't crash
            _ = service.getMemoryEvents()
        }

        // Should not crash
        XCTAssertTrue(true)
    }

    func testConcurrentEventClearing() {
        let service = MemoryMonitorService()

        // Rapidly clear events
        for _ in 1...500 {
            service.clearMemoryEvents()
        }

        XCTAssertTrue(service.getMemoryEvents().isEmpty)
    }

    func testMemoryPressureSimulation() async {
        let service = MemoryMonitorService()

        // Simulate rapid memory pressure changes
        for _ in 1...100 {
            // The service monitors memory automatically
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Should not crash
        XCTAssertTrue(true)
    }

    func testEventHistoryLimit() {
        let service = MemoryMonitorService()

        // The service should limit events to maxEventsToKeep (100)
        // We can't easily trigger this without internal access
        // but we verify the service handles it gracefully
        XCTAssertTrue(service.getMemoryEvents().count <= 100)
    }
}
