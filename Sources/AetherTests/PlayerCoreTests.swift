import XCTest
@testable import AetherCore

/// Tests for PlayerCore state machine and playback logic.
final class PlayerCoreTests: XCTestCase {

    @MainActor
    func testInitialState() {
        let core = PlayerCore()
        XCTAssertEqual(core.state, .idle)
        XCTAssertNil(core.currentChannel)
        XCTAssertFalse(core.isMuted)
        XCTAssertEqual(core.volume, 1.0, accuracy: 0.001)
        XCTAssertFalse(core.isPiPActive)
        XCTAssertEqual(core.retryCount, 0)
        XCTAssertEqual(core.channelList, [])
    }

    @MainActor
    func testSetVolumeClamping() {
        let core = PlayerCore()

        // Test upper bound
        core.setVolume(1.5)
        XCTAssertEqual(core.volume, 1.0, accuracy: 0.001)

        // Test lower bound
        core.setVolume(-0.5)
        XCTAssertEqual(core.volume, 0.0, accuracy: 0.001)

        // Test valid range
        core.setVolume(0.7)
        XCTAssertEqual(core.volume, 0.7, accuracy: 0.001)
    }

    @MainActor
    func testToggleMute() {
        let core = PlayerCore()
        XCTAssertFalse(core.isMuted)

        core.toggleMute()
        XCTAssertTrue(core.isMuted)

        core.toggleMute()
        XCTAssertFalse(core.isMuted)
    }

    @MainActor
    func testSetPiPActive() {
        let core = PlayerCore()
        XCTAssertFalse(core.isPiPActive)

        core.setPiPActive(true)
        XCTAssertTrue(core.isPiPActive)

        core.setPiPActive(false)
        XCTAssertFalse(core.isPiPActive)
    }

    @MainActor
    func testChannelNavigation() {
        let core = PlayerCore()
        let channels = [
            Channel(name: "Channel 1", streamURL: URL(string: "http://example.com/1")!),
            Channel(name: "Channel 2", streamURL: URL(string: "http://example.com/2")!),
            Channel(name: "Channel 3", streamURL: URL(string: "http://example.com/3")!)
        ]
        core.channelList = channels

        // Play first channel
        core.play(channels[0])
        XCTAssertEqual(core.currentChannel, channels[0])

        // Navigate to next
        core.playNext()
        XCTAssertEqual(core.currentChannel, channels[1])

        // Navigate to previous
        core.playPrevious()
        XCTAssertEqual(core.currentChannel, channels[0])
    }

    @MainActor
    func testChannelNavigationBounds() {
        let core = PlayerCore()
        let channels = [
            Channel(name: "Channel 1", streamURL: URL(string: "http://example.com/1")!),
            Channel(name: "Channel 2", streamURL: URL(string: "http://example.com/2")!)
        ]
        core.channelList = channels

        // Play first channel
        core.play(channels[0])

        // Try to go previous from first channel (should stay)
        core.playPrevious()
        XCTAssertEqual(core.currentChannel, channels[0])

        // Play last channel
        core.play(channels[1])

        // Try to go next from last channel (should stay)
        core.playNext()
        XCTAssertEqual(core.currentChannel, channels[1])
    }

    @MainActor
    func testStop() {
        let core = PlayerCore()
        let channel = Channel(name: "Test", streamURL: URL(string: "http://example.com/test")!)

        core.play(channel)
        XCTAssertNotNil(core.currentChannel)

        core.stop()
        XCTAssertNil(core.currentChannel)
        XCTAssertEqual(core.state, .idle)
    }

    @MainActor
    func testQualityPresets() {
        let core = PlayerCore()
        XCTAssertFalse(core.qualityPresets.isEmpty)
        XCTAssertTrue(core.qualityPresets.contains { $0.id == "auto" })
    }

    @MainActor
    func testSelectedQuality() {
        let core = PlayerCore()
        XCTAssertEqual(core.selectedQuality.id, "auto")

        let highQuality = StreamQuality(id: "high", label: "High", peakBitRate: 4_000_000)
        core.selectedQuality = highQuality
        XCTAssertEqual(core.selectedQuality.id, "high")
    }
}
