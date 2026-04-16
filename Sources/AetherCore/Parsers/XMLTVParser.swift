import Foundation

/// Parses an XMLTV-formatted string into `[EPGEntry]`.
///
/// Handles the standard XMLTV DTD used by most IPTV providers:
/// ```xml
/// <tv>
///   <channel id="cnn">...</channel>
///   <programme start="20240101120000 +0000" stop="20240101130000 +0000" channel="cnn">
///     <title>Breaking News</title>
///     <desc>Description...</desc>
///     <category>News</category>
///     <icon src="https://..."/>
///   </programme>
/// </tv>
/// ```
public actor XMLTVParser: NSObject {

    // MARK: - Public API

    /// Parses XMLTV XML data and returns all programme entries.
    public func parse(data: Data) throws -> [EPGEntry] {
        let delegate = XMLTVDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let ok = parser.parse()
        if !ok, let error = parser.parserError {
            throw EPGParseError.xmlError(error)
        }
        return delegate.entries
    }

    /// Convenience: parse UTF-8 string.
    public func parse(string: String) throws -> [EPGEntry] {
        guard let data = string.data(using: .utf8) else {
            throw EPGParseError.invalidEncoding
        }
        return try parse(data: data)
    }
}

// MARK: - Errors

public enum EPGParseError: Error, Sendable {
    case xmlError(Error)
    case invalidEncoding
}

// MARK: - NSXMLParserDelegate (private helper)

private final class XMLTVDelegate: NSObject, XMLParserDelegate {

    private(set) var entries: [EPGEntry] = []

    // Current programme being parsed
    private var currentChannelID: String?
    private var currentStart: Date?
    private var currentEnd: Date?
    private var currentTitle: String?
    private var currentDesc: String?
    private var currentCategory: String?
    private var currentIconURL: URL?
    private var currentCharacters: String = ""
    private var insideProgramme = false
    private var currentElement: String?

    // XMLTV date formatter: "20240101120000 +0000"
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // Also try without timezone offset: "20240101120000"
    private static let dateFormatterNoTZ: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string) ?? dateFormatterNoTZ.date(from: string)
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        currentElement = elementName
        currentCharacters = ""

        switch elementName {
        case "programme":
            insideProgramme = true
            currentChannelID = attributes["channel"]
            currentStart = attributes["start"].flatMap(Self.parseDate)
            currentEnd = (attributes["stop"] ?? attributes["end"]).flatMap(Self.parseDate)
            currentTitle = nil
            currentDesc = nil
            currentCategory = nil
            currentIconURL = nil

        case "icon" where insideProgramme:
            currentIconURL = attributes["src"].flatMap(URL.init(string:))

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentCharacters += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "title" where insideProgramme:
            currentTitle = text.isEmpty ? nil : text
        case "desc" where insideProgramme:
            currentDesc = text.isEmpty ? nil : text
        case "category" where insideProgramme:
            currentCategory = text.isEmpty ? nil : text
        case "programme":
            if let cid = currentChannelID,
               let start = currentStart,
               let end = currentEnd,
               let title = currentTitle {
                entries.append(EPGEntry(
                    channelID: cid,
                    title: title,
                    description: currentDesc,
                    start: start,
                    end: end,
                    category: currentCategory,
                    iconURL: currentIconURL
                ))
            }
            insideProgramme = false
            currentElement = nil
        default:
            break
        }
        currentCharacters = ""
    }
}
