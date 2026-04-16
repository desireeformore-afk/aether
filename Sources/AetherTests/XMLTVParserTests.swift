import XCTest
@testable import AetherCore

final class XMLTVParserTests: XCTestCase {

    private var parser: XMLTVParser!

    override func setUp() async throws {
        parser = XMLTVParser()
    }

    // MARK: - Basic parsing

    func testParsesBasicProgramme() async throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <tv>
          <channel id="cnn.us"><display-name>CNN</display-name></channel>
          <programme start="20240601120000 +0000" stop="20240601130000 +0000" channel="cnn.us">
            <title>Breaking News</title>
            <desc>Live coverage.</desc>
            <category>News</category>
          </programme>
        </tv>
        """

        let entries = try await parser.parse(string: xml)

        XCTAssertEqual(entries.count, 1)
        let e = entries[0]
        XCTAssertEqual(e.channelID, "cnn.us")
        XCTAssertEqual(e.title, "Breaking News")
        XCTAssertEqual(e.description, "Live coverage.")
        XCTAssertEqual(e.category, "News")
    }

    func testParsesMultipleProgrammes() async throws {
        let xml = """
        <?xml version="1.0"?>
        <tv>
          <programme start="20240601100000 +0000" stop="20240601110000 +0000" channel="ch1">
            <title>Morning Show</title>
          </programme>
          <programme start="20240601110000 +0000" stop="20240601120000 +0000" channel="ch1">
            <title>Afternoon Show</title>
          </programme>
          <programme start="20240601100000 +0000" stop="20240601110000 +0000" channel="ch2">
            <title>Sports</title>
          </programme>
        </tv>
        """

        let entries = try await parser.parse(string: xml)
        XCTAssertEqual(entries.count, 3)
        let ch1 = entries.filter { $0.channelID == "ch1" }
        XCTAssertEqual(ch1.count, 2)
    }

    func testParsesIconURL() async throws {
        let xml = """
        <?xml version="1.0"?>
        <tv>
          <programme start="20240601120000 +0000" stop="20240601130000 +0000" channel="test">
            <title>Test Show</title>
            <icon src="https://example.com/icon.png"/>
          </programme>
        </tv>
        """

        let entries = try await parser.parse(string: xml)
        XCTAssertEqual(entries[0].iconURL?.absoluteString, "https://example.com/icon.png")
    }

    func testEmptyXML() async throws {
        let xml = "<tv></tv>"
        let entries = try await parser.parse(string: xml)
        XCTAssertTrue(entries.isEmpty)
    }

    func testSkipsProgrammeMissingTitle() async throws {
        let xml = """
        <?xml version="1.0"?>
        <tv>
          <programme start="20240601120000 +0000" stop="20240601130000 +0000" channel="ch">
            <desc>No title here</desc>
          </programme>
        </tv>
        """
        let entries = try await parser.parse(string: xml)
        XCTAssertTrue(entries.isEmpty, "Entry without title should be skipped")
    }

    func testIsOnAir() async throws {
        let xml = """
        <?xml version="1.0"?>
        <tv>
          <programme start="20240601120000 +0000" stop="20240601130000 +0000" channel="ch">
            <title>Live</title>
          </programme>
        </tv>
        """
        let entries = try await parser.parse(string: xml)
        let e = entries[0]

        // Midpoint should be on-air
        let mid = e.start.addingTimeInterval(30 * 60)
        XCTAssertTrue(e.isOnAir(at: mid))

        // Before start — not on-air
        XCTAssertFalse(e.isOnAir(at: e.start.addingTimeInterval(-1)))

        // After end — not on-air
        XCTAssertFalse(e.isOnAir(at: e.end))
    }

    func testProgress() async throws {
        let xml = """
        <?xml version="1.0"?>
        <tv>
          <programme start="20240601120000 +0000" stop="20240601130000 +0000" channel="ch">
            <title>Live</title>
          </programme>
        </tv>
        """
        let entries = try await parser.parse(string: xml)
        let e = entries[0]
        let halfwayPoint = e.start.addingTimeInterval(30 * 60)
        XCTAssertEqual(e.progress(at: halfwayPoint), 0.5, accuracy: 0.001)
    }

    func testParsesDateWithoutTimezone() async throws {
        let xml = """
        <?xml version="1.0"?>
        <tv>
          <programme start="20240601120000" stop="20240601130000" channel="ch">
            <title>No TZ Show</title>
          </programme>
        </tv>
        """
        let entries = try await parser.parse(string: xml)
        XCTAssertEqual(entries.count, 1, "Should parse dates without timezone offset")
    }
}
