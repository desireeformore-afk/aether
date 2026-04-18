import XCTest
@testable import AetherCore

@MainActor
final class TrackServiceTests: XCTestCase {

    func testTrackServiceInitialization() {
        let service = TrackService()

        XCTAssertNotNil(service)
        XCTAssertTrue(service.availableAudioTracks.isEmpty)
        XCTAssertTrue(service.availableSubtitleTracks.isEmpty)
    }

    func testAudioTrackStructure() {
        let track = AudioTrack(
            id: "audio-1",
            language: "en",
            label: "English",
            isDefault: true
        )

        XCTAssertEqual(track.id, "audio-1")
        XCTAssertEqual(track.language, "en")
        XCTAssertEqual(track.label, "English")
        XCTAssertTrue(track.isDefault)
    }

    func testSubtitleTrackStructure() {
        let track = SubtitleTrackInfo(
            id: "sub-1",
            language: "en",
            label: "English",
            isForced: false,
            isDefault: true
        )

        XCTAssertEqual(track.id, "sub-1")
        XCTAssertEqual(track.language, "en")
        XCTAssertEqual(track.label, "English")
        XCTAssertFalse(track.isForced)
        XCTAssertTrue(track.isDefault)
    }

    func testTrackPreferences() {
        let preferences = TrackPreferences(
            preferredAudioLanguage: "en",
            preferredSubtitleLanguage: "es",
            subtitlesEnabled: true
        )

        XCTAssertEqual(preferences.preferredAudioLanguage, "en")
        XCTAssertEqual(preferences.preferredSubtitleLanguage, "es")
        XCTAssertTrue(preferences.subtitlesEnabled)
    }

    func testSaveAndLoadPreferences() {
        let service = TrackService()

        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)
        let preferences = TrackPreferences(
            preferredAudioLanguage: "en",
            preferredSubtitleLanguage: "es",
            subtitlesEnabled: true
        )

        service.savePreferences(for: channel, preferences: preferences)

        let loaded = service.loadPreferences(for: channel)
        XCTAssertEqual(loaded?.preferredAudioLanguage, "en")
        XCTAssertEqual(loaded?.preferredSubtitleLanguage, "es")
        XCTAssertTrue(loaded?.subtitlesEnabled ?? false)
    }
}
