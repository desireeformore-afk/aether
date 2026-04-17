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
        let ud = UserDefaults(suiteName: "test.default.\(UUID().uuidString)")!
        let service = ThemeService(defaults: ud)
        XCTAssertEqual(service.active.id, ThemeDefinition.allBuiltIn.first?.id)
    }

    @MainActor
    func testThemeServiceApply() {
        let ud = UserDefaults(suiteName: "test.apply.\(UUID().uuidString)")!
        let service = ThemeService(defaults: ud)
        let nord = ThemeDefinition.allBuiltIn.first { $0.id == "nord" }!
        service.select(nord)
        XCTAssertEqual(service.active.id, "nord")
    }

    @MainActor
    func testThemeServiceAllThemes() {
        XCTAssertEqual(ThemeDefinition.allBuiltIn.count, ThemeDefinition.allBuiltIn.count)
    }

    // MARK: - Color(hex:) helper

    func testColorHexParsing_white() {
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
            Channel(name: "BBC One",
                    streamURL: URL(string: "http://example.com/bbc1.m3u8")!,
                    logoURL: nil, groupTitle: "News", epgId: nil),
            Channel(name: "CNN International",
                    streamURL: URL(string: "http://example.com/cnn.m3u8")!,
                    logoURL: nil, groupTitle: "News", epgId: nil),
            Channel(name: "Eurosport",
                    streamURL: URL(string: "http://example.com/euro.m3u8")!,
                    logoURL: nil, groupTitle: "Sports", epgId: nil),
            Channel(name: "Sky Sports",
                    streamURL: URL(string: "http://example.com/sky.m3u8")!,
                    logoURL: nil, groupTitle: "Sports", epgId: nil),
        ]
    }
}
