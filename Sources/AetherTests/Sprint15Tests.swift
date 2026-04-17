import XCTest
@testable import AetherCore

// MARK: - Sprint 15 Tests: EPGTimeline auto-scroll, ThemeService persistence

final class Sprint15Tests: XCTestCase {

    // MARK: - ThemeService custom gradient persistence

    @MainActor
    func testCustomGradientPersisted() {
        let ud = UserDefaults(suiteName: "s15.persist.\(UUID().uuidString)")!
        let service = ThemeService(defaults: ud)

        let custom = ThemeDefinition(
            id: "custom_gradient",
            name: "My Purple",
            accentHex: "#7B61FF",
            background: .gradient(
                colors: ["#7B61FF", "#FF6060"],
                startPoint: "top",
                endPoint: "bottom"
            ),
            surfaceHex: "#1C1C1E",
            textHex: "#FFFFFF"
        )
        service.select(custom)

        // Reload from same UserDefaults
        let service2 = ThemeService(defaults: ud)
        XCTAssertEqual(service2.active.id, "custom_gradient")
        XCTAssertEqual(service2.active.name, "My Purple")
        if case .gradient(let colors, let start, _) = service2.active.background {
            XCTAssertEqual(colors.first, "#7B61FF")
            XCTAssertEqual(start, "top")
        } else {
            XCTFail("Expected gradient background")
        }
    }

    @MainActor
    func testAllThemesIncludesCustom() {
        let ud = UserDefaults(suiteName: "s15.all.\(UUID().uuidString)")!
        let service = ThemeService(defaults: ud)
        let builtInCount = ThemeDefinition.allBuiltIn.count

        // No custom yet
        XCTAssertEqual(service.allThemes.count, builtInCount)

        let custom = ThemeDefinition(
            id: "custom_gradient",
            name: "Wave",
            accentHex: "#00BFFF",
            background: .gradient(colors: ["#00BFFF", "#0033FF"], startPoint: "leading", endPoint: "trailing"),
            surfaceHex: "#111111",
            textHex: "#FFFFFF"
        )
        service.select(custom)
        XCTAssertEqual(service.allThemes.count, builtInCount + 1)
    }

    @MainActor
    func testBuiltInThemeDoesNotSaveCustomGradient() {
        let ud = UserDefaults(suiteName: "s15.builtin.\(UUID().uuidString)")!
        let service = ThemeService(defaults: ud)
        service.select(ThemeDefinition.allBuiltIn[0])
        XCTAssertNil(ud.data(forKey: "customGradientTheme"))
    }

    // MARK: - EPGTimelineView helpers (logic only, no SwiftUI)

    func testEPGEntriesFilteredToToday() {
        let now = Date()
        let entries = makeEntries(around: now)
        let today = entries.filter {
            Calendar.current.isDateInToday($0.start)
        }
        XCTAssertFalse(today.isEmpty)
    }

    func testIsOnAirTrueForCurrentEntry() {
        let now = Date()
        let entry = EPGEntry(
            channelID: "ch1",
            title: "Live Now",
            start: now.addingTimeInterval(-600),
            end: now.addingTimeInterval(600)
        )
        XCTAssertTrue(entry.isOnAir())
    }

    func testIsOnAirFalseForPastEntry() {
        let now = Date()
        let entry = EPGEntry(
            channelID: "ch1",
            title: "Past Show",
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(-1800)
        )
        XCTAssertFalse(entry.isOnAir())
    }

    func testProgressBetweenZeroAndOne() {
        let now = Date()
        let entry = EPGEntry(
            channelID: "ch1",
            title: "In Progress",
            start: now.addingTimeInterval(-1800),
            end: now.addingTimeInterval(1800)
        )
        let p = entry.progress()
        XCTAssertGreaterThan(p, 0)
        XCTAssertLessThan(p, 1)
        XCTAssertEqual(p, 0.5, accuracy: 0.05)
    }

    func testProgressZeroForFutureEntry() {
        let now = Date()
        let entry = EPGEntry(
            channelID: "ch1",
            title: "Future",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(4200)
        )
        XCTAssertEqual(entry.progress(), 0.0)
    }

    // MARK: - ThemeDefinition gradient backgrounds

    func testGradientThemeHasMultipleColors() {
        let sunset = ThemeDefinition.allBuiltIn.first { $0.id == "sunset" }!
        if case .gradient(let colors, _, _) = sunset.background {
            XCTAssertGreaterThanOrEqual(colors.count, 2)
        } else {
            XCTFail("Sunset must be gradient")
        }
    }

    func testSolidThemeBackground() {
        let def = ThemeDefinition.allBuiltIn.first { $0.id == "default" }!
        if case .solid(let hex) = def.background {
            XCTAssertTrue(hex.hasPrefix("#"))
        } else {
            XCTFail("Default must be solid")
        }
    }

    // MARK: - Helpers

    private func makeEntries(around date: Date) -> [EPGEntry] {
        (0..<6).map { i in
            let start = date.addingTimeInterval(Double(i - 2) * 3600)
            return EPGEntry(
                channelID: "ch1",
                title: "Show \(i)",
                start: start,
                end: start.addingTimeInterval(3600)
            )
        }
    }
}
