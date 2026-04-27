import XCTest
@testable import AetherCore

final class M3UParserTests: XCTestCase {

    // MARK: - Fixtures

    let basicM3U = """
        #EXTM3U
        #EXTINF:-1 tvg-id="bbc1" tvg-logo="https://example.com/bbc1.png" group-title="News",BBC One
        http://stream.example.com/bbc1
        #EXTINF:-1 tvg-id="cnn" tvg-logo="https://example.com/cnn.png" group-title="News",CNN
        http://stream.example.com/cnn
        """

    // MARK: - Tests

    func testBasicParse() throws {
        let channels = try M3UParser.parse(content: basicM3U)
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].name, "BBC One")
        XCTAssertEqual(channels[0].streamURL.absoluteString, "http://stream.example.com/bbc1")
        XCTAssertEqual(channels[1].name, "CNN")
    }

    func testNoHeader() throws {
        let m3u = """
            #EXTINF:-1 group-title="Sports",Sport Channel
            http://stream.example.com/sport
            """
        let channels = try M3UParser.parse(content: m3u)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "Sport Channel")
        XCTAssertEqual(channels[0].groupTitle, "Sports")
    }

    func testBOMHandling() throws {
        let withBOM = "\u{FEFF}" + basicM3U
        let channels = try M3UParser.parse(content: withBOM)
        XCTAssertEqual(channels.count, 2)
    }

    func testCRLFLineEndings() throws {
        let crlf = basicM3U.replacingOccurrences(of: "\n", with: "\r\n")
        let channels = try M3UParser.parse(content: crlf)
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].name, "BBC One")
    }

    func testMissingAttributes() throws {
        let m3u = """
            #EXTM3U
            #EXTINF:-1,Bare Channel
            http://stream.example.com/bare
            """
        let channels = try M3UParser.parse(content: m3u)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "Bare Channel")
        XCTAssertEqual(channels[0].groupTitle, "Uncategorized")
        XCTAssertNil(channels[0].epgId)
        XCTAssertNil(channels[0].logoURL)
    }

    func testEmptyContent() throws {
        let channels = try M3UParser.parse(content: "")
        XCTAssertTrue(channels.isEmpty)
    }

    func testGroupTitle() throws {
        let channels = try M3UParser.parse(content: basicM3U)
        XCTAssertEqual(channels[0].groupTitle, "News")
        XCTAssertEqual(channels[1].groupTitle, "News")
    }

    func testGroupTitleRawValueIsPreservedAndNormalizable() throws {
        let m3u = """
            #EXTM3U
            #EXTINF:-1 group-title="VIP | PL - 4K Action",Action Movie
            http://stream.example.com/movie.mp4
            """
        let channels = try M3UParser.parse(content: m3u)
        let category = CategoryNormalizer.normalize(
            rawName: channels[0].groupTitle,
            provider: .m3u,
            contentType: channels[0].contentType
        )

        XCTAssertEqual(channels[0].groupTitle, "VIP | PL - 4K Action")
        XCTAssertEqual(category.displayName, "Action")
        XCTAssertTrue(category.isPrimaryVisible)
    }

    func testLogoURL() throws {
        let channels = try M3UParser.parse(content: basicM3U)
        XCTAssertEqual(channels[0].logoURL?.absoluteString, "https://example.com/bbc1.png")
        XCTAssertEqual(channels[1].logoURL?.absoluteString, "https://example.com/cnn.png")
    }

    func testEpgId() throws {
        let channels = try M3UParser.parse(content: basicM3U)
        XCTAssertEqual(channels[0].epgId, "bbc1")
        XCTAssertEqual(channels[1].epgId, "cnn")
    }

    func testBlankLinesBetweenEntries() throws {
        let m3u = """
            #EXTM3U

            #EXTINF:-1 group-title="A",Channel A
            http://stream.example.com/a

            #EXTINF:-1 group-title="B",Channel B
            http://stream.example.com/b

            """
        let channels = try M3UParser.parse(content: m3u)
        XCTAssertEqual(channels.count, 2)
    }
}
