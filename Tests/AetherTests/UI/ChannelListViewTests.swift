import XCTest
import SwiftUI
@testable import AetherApp
@testable import AetherCore

@MainActor
final class ChannelListViewTests: XCTestCase {

    func testChannelListViewInitialization() {
        let playerCore = PlayerCore()
        let channels = [
            Channel(name: "Test Channel 1", streamURL: URL(string: "http://example.com/stream1")!),
            Channel(name: "Test Channel 2", streamURL: URL(string: "http://example.com/stream2")!)
        ]

        let view = ChannelListView(channels: channels, playerCore: playerCore)

        XCTAssertNotNil(view)
    }

    func testChannelListViewWithEmptyChannels() {
        let playerCore = PlayerCore()
        let channels: [Channel] = []

        let view = ChannelListView(channels: channels, playerCore: playerCore)

        XCTAssertNotNil(view)
    }

    func testChannelListViewWithFavorites() {
        let playerCore = PlayerCore()
        let channel1 = Channel(name: "Test Channel 1", streamURL: URL(string: "http://example.com/stream1")!)
        let channel2 = Channel(name: "Test Channel 2", streamURL: URL(string: "http://example.com/stream2")!)

        let channels = [channel1, channel2]
        let view = ChannelListView(channels: channels, playerCore: playerCore)

        XCTAssertNotNil(view)
    }
}
