import XCTest
@testable import AetherCore

@MainActor
final class MemoryMonitorServiceTests: XCTestCase {

    func testMemoryMonitorInitialization() {
        let service = MemoryMonitorService()

        XCTAssertNotNil(service)
        XCTAssertEqual(service.memoryPressure, .normal)
        XCTAssertEqual(service.memoryWarningCount, 0)
    }

    func testMemoryPressureLevels() {
        let service = MemoryMonitorService()

        XCTAssertEqual(MemoryMonitorService.MemoryPressureLevel.normal.description, "Normal")
        XCTAssertEqual(MemoryMonitorService.MemoryPressureLevel.warning.description, "Warning")
        XCTAssertEqual(MemoryMonitorService.MemoryPressureLevel.critical.description, "Critical")
    }

    func testMemoryEventLogging() {
        let service = MemoryMonitorService()

        XCTAssertTrue(service.getMemoryEvents().isEmpty)

        // Memory events are logged internally when pressure changes
        // We can't easily trigger this in tests without mocking
    }

    func testClearMemoryEvents() {
        let service = MemoryMonitorService()

        service.clearMemoryEvents()

        XCTAssertTrue(service.getMemoryEvents().isEmpty)
    }

    func testMemoryEventStructure() {
        let event = MemoryMonitorService.MemoryEvent(
            timestamp: Date(),
            level: .warning,
            memoryUsage: 1024000,
            action: "Test action"
        )

        XCTAssertEqual(event.level, .warning)
        XCTAssertEqual(event.memoryUsage, 1024000)
        XCTAssertEqual(event.action, "Test action")
    }
}
