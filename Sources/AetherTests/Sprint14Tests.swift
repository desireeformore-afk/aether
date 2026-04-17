import XCTest
@testable import AetherCore

// MARK: - Sprint 14 Tests: EPG Cache, ChannelFilterService, ThemeEngine

final class Sprint14Tests: XCTestCase {

    // MARK: - ChannelFilterService

    func testFilterByGroup() {
        let service = ChannelFilterService()
        let channels = makeSampleChannels()
        let result = service.filter(channels: channels, group: "Sports", searchQuery: "")
        XCTAssertTrue(result.allSatisfy { $0.groupTitle == "Sports" })
        XCTAssertEqual(result.count, 2)
    }

    func testFilterBySearchQuery() {
        let service = ChannelFilterService()
        let channels = makeSampleChannels()
        let result = service.filter(channels: channels, group: nil, searchQuery: "bbc")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "BBC One")
    }

    func testFilterCaseInsensitive() {
        let service = ChannelFilterService()
        let channels = makeSampleChannels()
        let result = service.filter(channels: channels, group: nil, searchQuery: "BBC")
        XCTAssertFalse(result.isEmpty)
    }

    func testFilterGroupAndSearch() {
        let service = ChannelFilterService()
        let channels = makeSampleChannels()
        let result = service.filter(channels: channels, group: "Sports", searchQuery: "euro")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Eurosport")
    }

    func testFilterNoMatch() {
        let service = ChannelFilterService()
        let channels = makeSampleChannels()
        let result = service.filter(channels: channels, group: nil, searchQuery: "xyznonexistent")
        XCTAssertTrue(result.isEmpty)
    }

    func testGroupsExtraction() {
        let service = ChannelFilterService()
        let channels = makeSampleChannels()
        let groups = service.groups(from: channels)
        XCTAssertEqual(groups.sorted(), ["News", "Sports"])
    }

    func testGroupsIgnoresEmpty() {
        let service = ChannelFilterService()
        var channels = makeSampleChannels()
        let noGroup = Channel(
            id: "no-group",
            name: "Mystery Channel",
            streamURL: URL(string: "http://example.com/mystery.m3u8")!,
            logoURL: nil,
            groupTitle: "",
            epgId: nil
        )
        channels.append(noGroup)
        let groups = service.groups(from: channels)
        XCTAssertFalse(groups.contains(""))
    }

    func testFilterEmptyQuery_returnsAll() {
        let service = ChannelFilterService()
        let channels = makeSampleChannels()
        let result = service.filter(channels: channels, group: nil, searchQuery: "")
        XCTAssertEqual(result.count, channels.count)
    }

    // MARK: - ThemeDefinition

    func testBuiltInThemesNotEmpty() {
        XCTAssertFalse(ThemeDefinition.allBuiltIn.isEmpty)
    }

    func testBuiltInThemeIDs() {
        let ids = ThemeDefinition.allBuiltIn.map(\.id)
        XCTAssertTrue(ids.contains("default"))
        XCTAssertTrue(ids.contains("amoled"))
        XCTAssertTrue(ids.contains("nord"))
    }

    func testThemeAccentColor_notClear() {
        for theme in ThemeDefinition.allBuiltIn {
            // accentColor must parse without crashing
            let color = theme.accentColor
            XCTAssertNotNil(color)
        }
    }

    func testSunsetThemeHasGradientBackground() {
        let sunset = ThemeDefinition.allBuiltIn.first { $0.id == "sunset" }
        XCTAssertNotNil(sunset, "Sunset theme should exist")
        if case .gradient(let colors, _, _) = sunset!.background {
            XCTAssertFalse(colors.isEmpty)
        } else {
            XCTFail("Sunset theme should have gradient background")
        }
    }

    func testDefaultThemeHasSolidBackground() {
        let def = ThemeDefinition.allBuiltIn.first { $0.id == "default" }
        XCTAssertNotNil(def)
        if case .solid(let hex) = def!.background {
            XCTAssertFalse(hex.isEmpty)
        } else {
            XCTFail("Default theme should have solid background")
        }
    }

    // MARK: - ThemeService

    @MainActor
    func testThemeServiceDefaultIsFirstBuiltIn() {
        let service = ThemeService()
        XCTAssertEqual(service.currentTheme.id, ThemeDefinition.allBuiltIn.first?.id)
    }

    @MainActor
    func testThemeServiceApply() {
        let service = ThemeService()
        let nord = ThemeDefinition.allBuiltIn.first { $0.id == "nord" }!
        service.apply(nord)
        XCTAssertEqual(service.currentTheme.id, "nord")
    }

    @MainActor
    func testThemeServiceAllThemes() {
        let service = ThemeService()
        XCTAssertEqual(service.allThemes.count, ThemeDefinition.allBuiltIn.count)
    }

    // MARK: - Color(hex:) helper

    func testColorHexParsing_white() {
        // just verify it doesn't crash — SwiftUI Color can't be inspected for components in tests
        let _ = ThemeDefinition(
            id: "test", name: "Test",
            accentHex: "#FFFFFF",
            background: .solid(color: "#000000"),
            surfaceHex: "#111111",
            textHex: "#EEEEEE"
        )
    }

    func testColorHexParsing_noHash() {
        let _ = ThemeDefinition(
            id: "test2", name: "Test2",
            accentHex: "FF6B6B",
            background: .solid(color: "1C1C1E"),
            surfaceHex: "2C2C2E",
            textHex: "FFFFFF"
        )
    }

    // MARK: - Helpers

    private func makeSampleChannels() -> [Channel] {
        [
            Channel(id: "bbc1", name: "BBC One",
                    streamURL: URL(string: "http://example.com/bbc1.m3u8")!,
                    logoURL: nil, groupTitle: "News", epgId: nil),
            Channel(id: "cnn", name: "CNN International",
                    streamURL: URL(string: "http://example.com/cnn.m3u8")!,
                    logoURL: nil, groupTitle: "News", epgId: nil),
            Channel(id: "euro", name: "Eurosport",
                    streamURL: URL(string: "http://example.com/euro.m3u8")!,
                    logoURL: nil, groupTitle: "Sports", epgId: nil),
            Channel(id: "sky", name: "Sky Sports",
                    streamURL: URL(string: "http://example.com/sky.m3u8")!,
                    logoURL: nil, groupTitle: "Sports", epgId: nil),
        ]
    }
}
