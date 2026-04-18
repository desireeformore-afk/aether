import XCTest
@testable import AetherCore

@MainActor
final class RecordingServiceStressTests: XCTestCase {

    func testMassRecordingScheduling() {
        let service = RecordingService()

        let channels = (1...100).map { i in
            Channel(name: "Channel \(i)", streamURL: URL(string: "http://example.com/stream\(i)")!)
        }

        // Schedule many recordings
        for (index, channel) in channels.enumerated() {
            let schedule = RecordingSchedule(
                id: UUID(),
                channel: channel,
                startTime: Date().addingTimeInterval(Double(index * 3600)),
                duration: 1800,
                recurring: false,
                title: "Recording \(index)"
            )
            service.scheduleRecording(schedule)
        }

        XCTAssertEqual(service.scheduledRecordings.count, 100)
    }

    func testRapidScheduleCancellation() {
        let service = RecordingService()

        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)

        // Schedule and cancel many recordings rapidly
        for i in 1...500 {
            let schedule = RecordingSchedule(
                id: UUID(),
                channel: channel,
                startTime: Date().addingTimeInterval(Double(i * 3600)),
                duration: 1800,
                recurring: false,
                title: "Recording \(i)"
            )
            service.scheduleRecording(schedule)
            service.cancelScheduledRecording(schedule.id)
        }

        XCTAssertEqual(service.scheduledRecordings.count, 0)
    }

    func testMassRecordingDeletion() {
        let service = RecordingService()

        // Create many completed recordings
        let recordings = (1...500).map { i in
            Recording(
                id: UUID(),
                channelName: "Channel \(i)",
                title: "Recording \(i)",
                startTime: Date(),
                duration: 1800,
                fileURL: URL(fileURLWithPath: "/tmp/recording\(i).mp4"),
                fileSize: 1024000
            )
        }

        service.completedRecordings = recordings
        XCTAssertEqual(service.completedRecordings.count, 500)

        // Delete all recordings
        for recording in recordings {
            service.deleteRecording(recording.id)
        }

        XCTAssertEqual(service.completedRecordings.count, 0)
    }

    func testConcurrentSettingsUpdates() {
        let service = RecordingService()

        let qualities: [RecordingSettings.Quality] = [.low, .medium, .high]
        let formats: [RecordingSettings.Format] = [.mp4, .mov, .ts]

        // Rapidly update settings
        for _ in 1...1000 {
            let settings = RecordingSettings(
                quality: qualities.randomElement()!,
                format: formats.randomElement()!,
                autoDeleteAfterDays: Int.random(in: 1...90)
            )
            service.updateSettings(settings)
        }

        // Should not crash
        XCTAssertTrue(true)
    }

    func testRecurringRecordingStress() {
        let service = RecordingService()

        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)

        // Schedule many recurring recordings
        for i in 1...100 {
            let schedule = RecordingSchedule(
                id: UUID(),
                channel: channel,
                startTime: Date().addingTimeInterval(Double(i * 3600)),
                duration: 1800,
                recurring: true,
                title: "Recurring Recording \(i)",
                recurrencePattern: .daily
            )
            service.scheduleRecording(schedule)
        }

        XCTAssertEqual(service.scheduledRecordings.count, 100)
    }
}
