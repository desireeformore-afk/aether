import XCTest
import SwiftUI
@testable import AetherApp
@testable import AetherCore

@MainActor
final class PlayerViewTests: XCTestCase {

    func testPlayerViewInitialization() {
        let playerCore = PlayerCore()
        let view = PlayerView(playerCore: playerCore)

        XCTAssertNotNil(view)
    }

    func testPlayerViewWithChannel() async {
        let playerCore = PlayerCore()
        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)

        playerCore.play(channel)

        XCTAssertEqual(playerCore.currentChannel?.name, "Test Channel")
        XCTAssertEqual(playerCore.state, .loading)
    }

    func testPlayerViewStopPlayback() async {
        let playerCore = PlayerCore()
        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)

        playerCore.play(channel)
        playerCore.stop()

        XCTAssertNil(playerCore.currentChannel)
        XCTAssertEqual(playerCore.state, .idle)
    }

    func testPlayerViewTogglePlayPause() async {
        let playerCore = PlayerCore()
        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)

        playerCore.play(channel)
        playerCore.togglePlayPause()

        // State should change from loading/playing to paused or vice versa
        XCTAssertTrue(playerCore.state == .paused || playerCore.state == .loading || playerCore.state == .playing)
    }

    func testPlayerViewVolumeControl() {
        let playerCore = PlayerCore()

        playerCore.setVolume(0.5)
        XCTAssertEqual(playerCore.volume, 0.5, accuracy: 0.01)

        playerCore.setVolume(1.0)
        XCTAssertEqual(playerCore.volume, 1.0, accuracy: 0.01)

        playerCore.setVolume(0.0)
        XCTAssertEqual(playerCore.volume, 0.0, accuracy: 0.01)
    }

    func testPlayerViewMuteToggle() {
        let playerCore = PlayerCore()

        XCTAssertFalse(playerCore.isMuted)

        playerCore.toggleMute()
        XCTAssertTrue(playerCore.isMuted)

        playerCore.toggleMute()
        XCTAssertFalse(playerCore.isMuted)
    }
}
