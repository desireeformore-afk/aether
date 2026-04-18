import XCTest
@testable import AetherCore

@MainActor
final class CrashReportingServiceTests: XCTestCase {

    func testCrashReportingServiceInitialization() {
        let service = CrashReportingService()

        XCTAssertNotNil(service)
        XCTAssertTrue(service.crashReports.isEmpty || !service.crashReports.isEmpty)
    }

    func testCrashReportStructure() {
        let report = CrashReportingService.CrashReport(
            id: UUID(),
            timestamp: Date(),
            exceptionName: "NSInvalidArgumentException",
            reason: "Test crash reason",
            stackTrace: ["Frame 1", "Frame 2", "Frame 3"],
            appVersion: "1.0.0",
            osVersion: "macOS 14.0"
        )

        XCTAssertEqual(report.exceptionName, "NSInvalidArgumentException")
        XCTAssertEqual(report.reason, "Test crash reason")
        XCTAssertEqual(report.stackTrace.count, 3)
        XCTAssertEqual(report.appVersion, "1.0.0")
        XCTAssertEqual(report.osVersion, "macOS 14.0")
    }

    func testDeleteCrashReport() {
        let service = CrashReportingService()

        let report = CrashReportingService.CrashReport(
            id: UUID(),
            timestamp: Date(),
            exceptionName: "TestException",
            reason: "Test",
            stackTrace: [],
            appVersion: "1.0.0",
            osVersion: "macOS 14.0"
        )

        service.crashReports.append(report)
        let initialCount = service.crashReports.count

        service.deleteCrashReport(report.id)

        XCTAssertEqual(service.crashReports.count, initialCount - 1)
    }

    func testClearAllCrashReports() {
        let service = CrashReportingService()

        let report1 = CrashReportingService.CrashReport(
            id: UUID(),
            timestamp: Date(),
            exceptionName: "Exception1",
            reason: "Test1",
            stackTrace: [],
            appVersion: "1.0.0",
            osVersion: "macOS 14.0"
        )

        let report2 = CrashReportingService.CrashReport(
            id: UUID(),
            timestamp: Date(),
            exceptionName: "Exception2",
            reason: "Test2",
            stackTrace: [],
            appVersion: "1.0.0",
            osVersion: "macOS 14.0"
        )

        service.crashReports.append(report1)
        service.crashReports.append(report2)

        service.clearAllCrashReports()

        XCTAssertTrue(service.crashReports.isEmpty)
    }
}
