import XCTest
@testable import AetherCore

@MainActor
final class RecordingServiceTests: XCTestCase {

    func testRecordingServiceInitialization() {
        let service = RecordingService()

        XCTAssertNotNil(service)
        XCTAssertTrue(service.activeRecordings.isEmpty)
        XCTAssertTrue(service.completedRecordings.isEmpty)
        XCTAssertTrue(service.scheduledRecordings.isEmpty)
    }

    func testScheduleRecording() {
        let service = RecordingService()

        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)
        let startTime = Date().addingTimeInterval(3600) // 1 hour from now
        let duration = 1800 // 30 minutes

        let schedule = RecordingSchedule(
            id: UUID(),
            channel: channel,
            startTime: startTime,
            duration: duration,
            recurring: false,
            title: "Test Recording"
        )

        service.scheduleRecording(schedule)

        XCTAssertEqual(service.scheduledRecordings.count, 1)
        XCTAssertEqual(service.scheduledRecordings.first?.title, "Test Recording")
    }

    func testCancelScheduledRecording() {
        let service = RecordingService()

        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)
        let startTime = Date().addingTimeInterval(3600)
        let duration = 1800

        let schedule = RecordingSchedule(
            id: UUID(),
            channel: channel,
            startTime: startTime,
            duration: duration,
            recurring: false,
            title: "Test Recording"
        )

        service.scheduleRecording(schedule)
        XCTAssertEqual(service.scheduledRecordings.count, 1)

        service.cancelScheduledRecording(schedule.id)
        XCTAssertEqual(service.scheduledRecordings.count, 0)
    }

    func testDeleteRecording() {
        let service = RecordingService()

        let recording = Recording(
            id: UUID(),
            channelName: "Test Channel",
            title: "Test Recording",
            startTime: Date(),
            duration: 1800,
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            fileSize: 1024000
        )

        service.completedRecordings.append(recording)
        XCTAssertEqual(service.completedRecordings.count, 1)

        service.deleteRecording(recording.id)
        XCTAssertEqual(service.completedRecordings.count, 0)
    }

    func testRecordingSettings() {
        let service = RecordingService()

        let settings = RecordingSettings(
            quality: .high,
            format: .mp4,
            autoDeleteAfterDays: 30
        )

        service.updateSettings(settings)

        XCTAssertEqual(service.settings.quality, .high)
        XCTAssertEqual(service.settings.format, .mp4)
        XCTAssertEqual(service.settings.autoDeleteAfterDays, 30)
    }
}
