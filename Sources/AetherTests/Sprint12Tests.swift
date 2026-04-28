import XCTest
@testable import AetherCore

// MARK: - SRTParser Tests

final class SRTParserTests: XCTestCase {

    // MARK: - Basic parsing

    func testParseSingleCue() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Hello, world!
        """
        let cues = SRTParser.parse(srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Hello, world!")
        XCTAssertEqual(cues[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 4.0, accuracy: 0.001)
    }

    func testParseMultipleCues() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        First subtitle

        2
        00:00:05,500 --> 00:00:08,000
        Second subtitle

        3
        00:01:00,000 --> 00:01:03,000
        Third subtitle
        """
        let cues = SRTParser.parse(srt)
        XCTAssertEqual(cues.count, 3)
        XCTAssertEqual(cues[1].start, 5.5, accuracy: 0.001)
        XCTAssertEqual(cues[2].start, 60.0, accuracy: 0.001)
    }

    func testParseMultilineText() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Line one
        Line two
        """
        let cues = SRTParser.parse(srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssert(cues[0].text.contains("Line one"))
        XCTAssert(cues[0].text.contains("Line two"))
    }

    func testParseEmptyString() {
        let cues = SRTParser.parse("")
        XCTAssertTrue(cues.isEmpty)
    }

    func testParseWindowsLineEndings() {
        let srt = "1\r\n00:00:01,000 --> 00:00:04,000\r\nHello\r\n"
        let cues = SRTParser.parse(srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text.trimmingCharacters(in: .whitespaces), "Hello")
    }

    func testTimestampWithHours() {
        let srt = """
        1
        01:30:00,000 --> 01:30:05,500
        Late subtitle
        """
        let cues = SRTParser.parse(srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].start, 5400.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 5405.5, accuracy: 0.001)
    }

    func testActiveCueAtTime() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        First

        2
        00:00:05,000 --> 00:00:08,000
        Second
        """
        let cues = SRTParser.parse(srt)

        XCTAssertNil(cues.first { $0.start <= 0.5 && $0.end > 0.5 })
        let at2 = cues.first { $0.start <= 2.0 && $0.end > 2.0 }
        XCTAssertEqual(at2?.text, "First")
        XCTAssertNil(cues.first { $0.start <= 4.5 && $0.end > 4.5 })
        let at6 = cues.first { $0.start <= 6.0 && $0.end > 6.0 }
        XCTAssertEqual(at6?.text, "Second")
        XCTAssertNil(cues.first { $0.start <= 9.0 && $0.end > 9.0 })
    }

    func testHTMLTagStripping() {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        <i>Italic</i> and <b>bold</b>
        """
        let cues = SRTParser.parse(srt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertFalse(cues[0].text.contains("<i>"))
        XCTAssertFalse(cues[0].text.contains("</b>"))
        XCTAssert(cues[0].text.contains("Italic"))
        XCTAssert(cues[0].text.contains("bold"))
    }

    func testWebVTTFormat() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        WebVTT subtitle
        """
        let cues = SRTParser.parse(vtt)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "WebVTT subtitle")
        XCTAssertEqual(cues[0].start, 1.0, accuracy: 0.001)
    }
}

// MARK: - PlayerPlaybackConfig Tests

final class PlayerPlaybackConfigTests: XCTestCase {

    func testNetworkCachingValuesArePositive() {
        XCTAssertGreaterThan(PlayerPlaybackConfig.liveNetworkCachingMilliseconds, 0)
        XCTAssertGreaterThan(PlayerPlaybackConfig.vodNetworkCachingMilliseconds, 0)
    }

    func testNetworkCachingValuesMatchCurrentPlaybackPolicy() {
        XCTAssertEqual(PlayerPlaybackConfig.liveNetworkCachingMilliseconds, 1500)
        XCTAssertEqual(PlayerPlaybackConfig.vodNetworkCachingMilliseconds, 6000)
        XCTAssertEqual(PlayerPlaybackConfig.strengthenedVODNetworkCachingMilliseconds, 12000)
        XCTAssertGreaterThan(PlayerPlaybackConfig.vodNetworkCachingMilliseconds,
                             PlayerPlaybackConfig.liveNetworkCachingMilliseconds)
    }

    func testNetworkCachingSelectorUsesStreamType() {
        XCTAssertEqual(PlayerPlaybackConfig.networkCachingMilliseconds(isLiveStream: true), 1500)
        XCTAssertEqual(PlayerPlaybackConfig.networkCachingMilliseconds(isLiveStream: false), 6000)
        XCTAssertEqual(PlayerPlaybackConfig.networkCachingMilliseconds(isLiveStream: false, cachingProfile: .strengthened), 12000)
    }
}
