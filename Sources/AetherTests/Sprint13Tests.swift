import XCTest
@testable import AetherCore

// MARK: - Sprint 13 Tests: Cross-Platform Polish & Release Prep

/// Tests for AetherCore components introduced or enhanced in Sprint 13.
final class Sprint13Tests: XCTestCase {

    // MARK: - PlayerCore cross-platform API

    @MainActor
    func testPlayerCoreInitialState() throws {
        let core = try PlayerCoreTestSupport.makePlayerCore()
        XCTAssertEqual(core.state, .idle)
        XCTAssertNil(core.currentChannel)
        XCTAssertFalse(core.isMuted)
        XCTAssertEqual(core.volume, 1.0, accuracy: 0.001)
        XCTAssertFalse(core.isPiPActive)
        XCTAssertEqual(core.channelList, [])
    }

    @MainActor
    func testSetPiPActive() throws {
        let core = try PlayerCoreTestSupport.makePlayerCore()
        XCTAssertFalse(core.isPiPActive)
        core.setPiPActive(true)
        XCTAssertTrue(core.isPiPActive)
        core.setPiPActive(false)
        XCTAssertFalse(core.isPiPActive)
    }

    @MainActor
    func testSetVolumeClamping() throws {
        let core = try PlayerCoreTestSupport.makePlayerCore()
        core.setVolume(1.5)
        XCTAssertEqual(core.volume, 1.0, accuracy: 0.001)
        core.setVolume(-0.5)
        XCTAssertEqual(core.volume, 0.0, accuracy: 0.001)
        core.setVolume(0.7)
        XCTAssertEqual(core.volume, 0.7, accuracy: 0.001)
    }

    @MainActor
    func testToggleMute() throws {
        let core = try PlayerCoreTestSupport.makePlayerCore()
        XCTAssertFalse(core.isMuted)
        core.toggleMute()
        XCTAssertTrue(core.isMuted)
        core.toggleMute()
        XCTAssertFalse(core.isMuted)
    }

    @MainActor
    func testPlayNextAndPrevious_withChannelList() throws {
        let core = try PlayerCoreTestSupport.makePlayerCore()
        let channels = [
            makeChannel(name: "CH1"),
            makeChannel(name: "CH2"),
            makeChannel(name: "CH3"),
        ]
        core.channelList = channels

        // No current channel — playNext should do nothing
        core.playNext()
        XCTAssertNil(core.currentChannel)

        // Set current channel and navigate
        core.play(channels[0])
        core.playNext()
        XCTAssertEqual(core.currentChannel?.name, "CH2")

        core.playNext()
        XCTAssertEqual(core.currentChannel?.name, "CH3")

        // At end — playNext stays put
        core.playNext()
        XCTAssertEqual(core.currentChannel?.name, "CH3")

        core.playPrevious()
        XCTAssertEqual(core.currentChannel?.name, "CH2")
    }

    @MainActor
    func testStopClearsState() throws {
        let core = try PlayerCoreTestSupport.makePlayerCore()
        let channel = makeChannel(name: "Test")
        core.channelList = [channel]
        core.play(channel)
        XCTAssertNotNil(core.currentChannel)

        core.stop()
        XCTAssertNil(core.currentChannel)
        XCTAssertEqual(core.state, .idle)
        XCTAssertEqual(core.retryCount, 0)
    }

    // MARK: - Channel model

    func testChannelEquality() {
        let ch1 = makeChannel(name: "Alpha")
        let ch2 = makeChannel(name: "Beta")
        XCTAssertNotEqual(ch1, ch2)
    }

    func testChannelLogoURL_nilWhenNotProvided() {
        let ch = makeChannel(name: "Test")
        XCTAssertNil(ch.logoURL)
    }

    func testChannelWithLogoURL() {
        let url = URL(string: "https://example.com/logo.png")!
        let ch = Channel(
            name: "Logo Channel",
            streamURL: URL(string: "https://example.com/stream")!,
            logoURL: url,
            groupTitle: "News"
        )
        XCTAssertEqual(ch.logoURL, url)
    }

    // MARK: - EPGEntry progress

    func testEPGEntryProgress_atMidpoint() {
        let now = Date()
        let start = now.addingTimeInterval(-300) // 5 min ago
        let end   = now.addingTimeInterval(300)  // 5 min from now
        let entry = EPGEntry(
            channelID: "c1",
            title: "News",
            start: start,
            end: end
        )
        let progress = entry.progress(at: now)
        XCTAssertEqual(progress, 0.5, accuracy: 0.05)
    }

    func testEPGEntryProgress_beforeStart() {
        let now = Date()
        let entry = EPGEntry(
            channelID: "c1",
            title: "Future Show",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(3660)
        )
        XCTAssertEqual(entry.progress(at: now), 0.0, accuracy: 0.001)
    }

    func testEPGEntryProgress_afterEnd() {
        let now = Date()
        let entry = EPGEntry(
            channelID: "c1",
            title: "Past Show",
            start: now.addingTimeInterval(-3660),
            end: now.addingTimeInterval(-60)
        )
        XCTAssertEqual(entry.progress(at: now), 1.0, accuracy: 0.001)
    }

    func testEPGEntryIsOnAir() {
        let now = Date()
        let current = EPGEntry(
            channelID: "c1",
            title: "On Air",
            start: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(60)
        )
        XCTAssertTrue(current.isOnAir(at: now))

        let past = EPGEntry(
            channelID: "c1",
            title: "Ended",
            start: now.addingTimeInterval(-120),
            end: now.addingTimeInterval(-10)
        )
        XCTAssertFalse(past.isOnAir(at: now))
    }

    // MARK: - StreamQuality

    func testStreamQualityPresets_nonEmpty() {
        let presets = StreamQualityPreset.allCases
        XCTAssertFalse(presets.isEmpty)
    }

    func testStreamQualityAutoLabel_nonEmpty() {
        let auto = StreamQualityPreset.auto.quality
        XCTAssertFalse(auto.label.isEmpty)
    }

    func testAllQualityPresetsHaveNonEmptyLabels() {
        for preset in StreamQualityPreset.allCases {
            XCTAssertFalse(preset.quality.label.isEmpty, "Preset \(preset) has empty label")
        }
    }

    // MARK: - SleepTimerService

    @MainActor
    func testSleepTimerService_initiallyInactive() {
        let svc = SleepTimerService()
        XCTAssertFalse(svc.isActive)
    }

    @MainActor
    func testSleepTimerService_startAndCancel() {
        let svc = SleepTimerService()
        svc.start(duration: .thirtyMinutes)
        XCTAssertTrue(svc.isActive)
        svc.cancel()
        XCTAssertFalse(svc.isActive)
    }

    @MainActor
    func testSleepTimerDuration_allCasesIdentifiable() {
        let durations = SleepTimerDuration.allCases
        XCTAssertFalse(durations.isEmpty)
        // All IDs unique
        let ids = Set(durations.map { $0.id })
        XCTAssertEqual(ids.count, durations.count)
    }

    // MARK: - Helpers

    private func makeChannel(name: String) -> Channel {
        Channel(
            name: name,
            streamURL: URL(string: "https://example.com/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)")!,
            groupTitle: "Test"
        )
    }
}
