import XCTest
@testable import AetherCore

final class RecordingServiceTests: XCTestCase {
    var service: RecordingService!
    var userDefaults: UserDefaults!
    var testChannel: Channel!

    @MainActor
    override func setUp() async throws {
        userDefaults = UserDefaults(suiteName: "test.aether.recordings")!
        userDefaults.removePersistentDomain(forName: "test.aether.recordings")
        service = RecordingService(userDefaults: userDefaults)

        testChannel = Channel(
            name: "Test Channel",
            streamURL: URL(string: "http://example.com/stream.m3u8")!
        )
    }

    override func tearDown() async throws {
        // Clean up test recordings
        let recordingsDir = service.settings.recordingsDirectory
        try? FileManager.default.removeItem(at: recordingsDir)

        userDefaults.removePersistentDomain(forName: "test.aether.recordings")
        userDefaults = nil
        service = nil
        testChannel = nil
    }

    // MARK: - Recording Tests

    @MainActor
    func testStartRecording() throws {
        let recordingId = try service.startRecording(channel: testChannel)

        XCTAssertNotNil(service.activeRecordings[recordingId])
        XCTAssertEqual(service.activeRecordings[recordingId]?.channelName, "Test Channel")
        XCTAssertFalse(service.activeRecordings[recordingId]?.isComplete ?? true)
    }

    @MainActor
    func testStopRecording() async throws {
        let recordingId = try service.startRecording(channel: testChannel)
        XCTAssertEqual(service.activeRecordings.count, 1)

        try await service.stopRecording(recordingId)

        XCTAssertEqual(service.activeRecordings.count, 0)
        XCTAssertEqual(service.completedRecordings.count, 1)
        XCTAssertTrue(service.completedRecordings[0].isComplete)
    }

    @MainActor
    func testDeleteRecording() async throws {
        let recordingId = try service.startRecording(channel: testChannel)
        try await service.stopRecording(recordingId)

        XCTAssertEqual(service.completedRecordings.count, 1)

        try service.deleteRecording(recordingId)

        XCTAssertEqual(service.completedRecordings.count, 0)
    }

    @MainActor
    func testDeleteNonExistentRecording() {
        XCTAssertThrowsError(try service.deleteRecording(UUID())) { error in
            XCTAssertEqual(error as? RecordingError, .recordingNotFound)
        }
    }

    // MARK: - Schedule Tests

    @MainActor
    func testScheduleRecording() throws {
        let schedule = RecordingSchedule(
            channelId: testChannel.id,
            channelName: testChannel.name,
            startTime: Date().addingTimeInterval(3600),
            duration: 1800
        )

        try service.scheduleRecording(schedule)

        XCTAssertEqual(service.scheduledRecordings.count, 1)
        XCTAssertEqual(service.scheduledRecordings[0].channelName, "Test Channel")
    }

    @MainActor
    func testCancelSchedule() throws {
        let schedule = RecordingSchedule(
            channelId: testChannel.id,
            channelName: testChannel.name,
            startTime: Date().addingTimeInterval(3600),
            duration: 1800
        )

        try service.scheduleRecording(schedule)
        XCTAssertEqual(service.scheduledRecordings.count, 1)

        try service.cancelSchedule(schedule.id)
        XCTAssertEqual(service.scheduledRecordings.count, 0)
    }

    @MainActor
    func testUpdateSchedule() throws {
        var schedule = RecordingSchedule(
            channelId: testChannel.id,
            channelName: testChannel.name,
            startTime: Date().addingTimeInterval(3600),
            duration: 1800
        )

        try service.scheduleRecording(schedule)

        schedule.duration = 3600
        try service.updateSchedule(schedule)

        XCTAssertEqual(service.scheduledRecordings[0].duration, 3600)
    }

    // MARK: - Settings Tests

    @MainActor
    func testUpdateSettings() throws {
        var newSettings = service.settings
        newSettings.autoDeleteAfterDays = 60

        try service.updateSettings(newSettings)

        XCTAssertEqual(service.settings.autoDeleteAfterDays, 60)
    }

    @MainActor
    func testRecordingQuality() {
        XCTAssertEqual(RecordingQuality.low.bitrate, 1_500_000)
        XCTAssertEqual(RecordingQuality.medium.bitrate, 3_000_000)
        XCTAssertEqual(RecordingQuality.high.bitrate, 6_000_000)
        XCTAssertEqual(RecordingQuality.source.bitrate, 0)
    }

    // MARK: - Recording Model Tests

    func testRecordingFileSizeFormatted() {
        let recording = Recording(
            channelName: "Test",
            channelId: UUID(),
            startTime: Date(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            fileSize: 1_048_576 // 1 MB
        )

        XCTAssertTrue(recording.fileSizeFormatted.contains("MB"))
    }

    func testRecordingDurationFormatted() {
        let recording = Recording(
            channelName: "Test",
            channelId: UUID(),
            startTime: Date(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: 3665 // 1h 1m 5s
        )

        XCTAssertEqual(recording.durationFormatted, "1:01:05")
    }

    func testRecordingDurationFormattedShort() {
        let recording = Recording(
            channelName: "Test",
            channelId: UUID(),
            startTime: Date(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            duration: 125 // 2m 5s
        )

        XCTAssertEqual(recording.durationFormatted, "2:05")
    }
}

final class TimeshiftServiceTests: XCTestCase {
    var service: TimeshiftService!
    var testChannelId: UUID!

    @MainActor
    override func setUp() async throws {
        service = TimeshiftService()
        testChannelId = UUID()
    }

    override func tearDown() async throws {
        service = nil
        testChannelId = nil
    }

    @MainActor
    func testStartBuffering() throws {
        XCTAssertFalse(service.isBuffering)

        try service.startBuffering(for: testChannelId)

        XCTAssertTrue(service.isBuffering)
        XCTAssertFalse(service.isPaused)
    }

    @MainActor
    func testStopBuffering() throws {
        try service.startBuffering(for: testChannelId)
        XCTAssertTrue(service.isBuffering)

        service.stopBuffering()

        XCTAssertFalse(service.isBuffering)
        XCTAssertFalse(service.isPaused)
    }

    @MainActor
    func testPauseResume() throws {
        try service.startBuffering(for: testChannelId)

        service.pause()
        XCTAssertTrue(service.isPaused)

        service.resume()
        XCTAssertFalse(service.isPaused)
    }

    @MainActor
    func testSeekWithoutBuffering() {
        XCTAssertThrowsError(try service.seek(to: 10)) { error in
            XCTAssertEqual(error as? TimeshiftError, .notBuffering)
        }
    }

    @MainActor
    func testJumpBackWithoutBuffering() {
        XCTAssertThrowsError(try service.jumpBack(seconds: 10)) { error in
            XCTAssertEqual(error as? TimeshiftError, .notBuffering)
        }
    }

    @MainActor
    func testJumpForwardWithoutBuffering() {
        XCTAssertThrowsError(try service.jumpForward(seconds: 10)) { error in
            XCTAssertEqual(error as? TimeshiftError, .notBuffering)
        }
    }
}
