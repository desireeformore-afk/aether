import XCTest
@testable import AetherCore

/// Tests for ThemeService persistence and theme management.
final class ThemeServiceTests: XCTestCase {

    @MainActor
    func testThemeServiceInitialization() {
        let ud = UserDefaults(suiteName: "core.init.\(UUID().uuidString)")!
        let service = ThemeService(defaults: ud)
        XCTAssertNotNil(service)
        XCTAssertNotNil(service.active)
    }

    @MainActor
    func testThemeSelection() {
        let ud = UserDefaults(suiteName: "core.select.\(UUID().uuidString)")!
        let service = ThemeService(defaults: ud)
        let themes = ThemeDefinition.allBuiltIn
        XCTAssertFalse(themes.isEmpty)

        let first = themes[0]
        service.select(first)
        XCTAssertEqual(service.active.id, first.id)

        if themes.count > 1 {
            let second = themes[1]
            service.select(second)
            XCTAssertEqual(service.active.id, second.id)
        }
    }

    @MainActor
    func testAllBuiltInThemes() {
        let themes = ThemeDefinition.allBuiltIn
        XCTAssertFalse(themes.isEmpty)
        for theme in themes {
            XCTAssertFalse(theme.id.isEmpty)
            XCTAssertFalse(theme.name.isEmpty)
        }
    }
}

/// Tests for StreamQuality and StreamQualityService.
final class StreamQualityTests: XCTestCase {

    func testStreamQualityPresets() {
        let presets = StreamQualityPreset.allCases
        XCTAssertFalse(presets.isEmpty)

        for preset in presets {
            let quality = preset.quality
            XCTAssertFalse(quality.id.isEmpty)
            XCTAssertFalse(quality.label.isEmpty)
            XCTAssertGreaterThanOrEqual(quality.peakBitRate, 0)
        }
    }

    func testAutoQuality() {
        let auto = StreamQuality.auto
        XCTAssertEqual(auto.id, "auto")
        XCTAssertEqual(auto.peakBitRate, 0)
    }

    func testStreamQualityEquality() {
        let q1 = StreamQuality(id: "test", label: "Test", peakBitRate: 1000)
        let q2 = StreamQuality(id: "test", label: "Test", peakBitRate: 1000)
        let q3 = StreamQuality(id: "other", label: "Other", peakBitRate: 2000)

        XCTAssertEqual(q1, q2)
        XCTAssertNotEqual(q1, q3)
    }
}

/// Tests for Channel model.
final class ChannelTests: XCTestCase {

    func testChannelCreation() {
        let url = URL(string: "http://example.com/stream")!
        let logoURL = URL(string: "http://example.com/logo.png")
        let channel = Channel(
            name: "Test Channel",
            streamURL: url,
            logoURL: logoURL,
            groupTitle: "Test Group",
            epgId: "test-epg-id"
        )

        XCTAssertEqual(channel.name, "Test Channel")
        XCTAssertEqual(channel.streamURL, url)
        XCTAssertEqual(channel.logoURL, logoURL)
        XCTAssertEqual(channel.groupTitle, "Test Group")
        XCTAssertEqual(channel.epgId, "test-epg-id")
    }

    func testChannelWithDefaults() {
        let url = URL(string: "http://example.com/stream")!
        let channel = Channel(name: "Simple Channel", streamURL: url)

        XCTAssertEqual(channel.name, "Simple Channel")
        XCTAssertEqual(channel.streamURL, url)
        XCTAssertNil(channel.logoURL)
        XCTAssertEqual(channel.groupTitle, "Uncategorized")
        XCTAssertNil(channel.epgId)
    }

    func testChannelEquality() {
        let url = URL(string: "http://example.com/stream")!
        let channel1 = Channel(name: "Test", streamURL: url)
        let channel2 = Channel(name: "Test", streamURL: url)

        // Channels with different IDs should not be equal
        XCTAssertNotEqual(channel1, channel2)

        // Same instance should be equal
        XCTAssertEqual(channel1, channel1)
    }
}
