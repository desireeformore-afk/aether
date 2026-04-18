import XCTest
@testable import AetherCore

@MainActor
final class PlayerCoreStressTests: XCTestCase {

    func testRapidChannelSwitching() async {
        let playerCore = PlayerCore()

        let channels = (1...50).map { i in
            Channel(name: "Channel \(i)", streamURL: URL(string: "http://example.com/stream\(i)")!)
        }

        // Rapidly switch between channels
        for channel in channels {
            playerCore.play(channel)
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Should not crash and should have the last channel
        XCTAssertEqual(playerCore.currentChannel?.name, "Channel 50")
    }

    func testConcurrentPlayStopOperations() async {
        let playerCore = PlayerCore()

        let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)

        // Perform many play/stop operations rapidly
        for _ in 1...100 {
            playerCore.play(channel)
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
            playerCore.stop()
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }

        // Should not crash
        XCTAssertTrue(true)
    }

    func testVolumeControlStress() {
        let playerCore = PlayerCore()

        // Rapidly change volume
        for i in 0...1000 {
            let volume = Float(i % 101) / 100.0
            playerCore.setVolume(volume)
        }

        // Should not crash
        XCTAssertTrue(playerCore.volume >= 0.0 && playerCore.volume <= 1.0)
    }

    func testMuteToggleStress() {
        let playerCore = PlayerCore()

        // Toggle mute many times
        for _ in 1...1000 {
            playerCore.toggleMute()
        }

        // Should not crash
        XCTAssertTrue(true)
    }

    func testChannelListNavigation() async {
        let playerCore = PlayerCore()

        let channels = (1...100).map { i in
            Channel(name: "Channel \(i)", streamURL: URL(string: "http://example.com/stream\(i)")!)
        }

        playerCore.channelList = channels
        playerCore.play(channels[0])

        // Navigate through all channels
        for _ in 1..<channels.count {
            playerCore.playNext()
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Should wrap around or stop at last channel
        XCTAssertNotNil(playerCore.currentChannel)
    }

    func testMemoryLeakPrevention() async {
        weak var weakPlayer: PlayerCore?

        do {
            let player = PlayerCore()
            weakPlayer = player

            let channel = Channel(name: "Test Channel", streamURL: URL(string: "http://example.com/stream")!)

            // Perform operations
            for _ in 1...50 {
                player.play(channel)
                try? await Task.sleep(nanoseconds: 10_000_000)
                player.stop()
            }
        }

        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Player should be deallocated
        XCTAssertNil(weakPlayer, "PlayerCore should be deallocated")
    }
}
