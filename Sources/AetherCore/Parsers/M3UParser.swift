import Foundation

/// Errors thrown by `M3UParser`.
public enum M3UParserError: Error, LocalizedError, Sendable {
    case invalidContent
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case .invalidContent:
            return "File does not look like a valid M3U playlist (missing #EXTM3U header)."
        case .invalidURL(let s):
            return "Invalid stream URL in playlist: \(s)"
        }
    }
}

/// Parser for M3U/M3U8 playlist files.
///
/// Parses IPTV playlists in M3U format, extracting channel metadata including
/// stream URLs, logos, EPG IDs, and group categories.
///
/// ## Topics
///
/// ### Parsing Playlists
/// - ``parse(content:)``
///
/// ### Errors
/// - ``M3UParserError``
///
/// ## Example
///
/// ```swift
/// let m3uContent = """
/// #EXTM3U
/// #EXTINF:-1 tvg-id="bbc1" tvg-logo="http://example.com/logo.png" group-title="News",BBC One
/// http://stream.example.com/bbc1
/// """
/// let channels = try M3UParser.parse(content: m3uContent)
/// ```
public struct M3UParser: Sendable {

    /// Parses M3U content from a `String` and returns an array of `Channel`.
    ///
    /// Supports both M3U and M3U8 formats with extended metadata including:
    /// - `tvg-id`: EPG identifier
    /// - `tvg-logo`: Channel logo URL
    /// - `group-title`: Channel category
    ///
    /// - Parameter content: Raw M3U playlist text.
    /// - Returns: Parsed channels in order of appearance.
    /// - Throws: ``M3UParserError`` on unrecoverable format errors.
    public static func parse(content: String) throws -> [Channel] {
        // Strip UTF-8 BOM if present
        var text = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content

        // Normalize line endings
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")

        var lines = text.components(separatedBy: "\n")

        // Validate: must contain at least one #EXTINF or #EXTM3U line
        // Empty content is valid and returns an empty channel list.
        let hasM3UContent = lines.contains { $0.hasPrefix("#EXTM3U") || $0.hasPrefix("#EXTINF:") }
        guard hasM3UContent else {
            // Empty or whitespace-only input → empty playlist (not an error)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [] }
            throw M3UParserError.invalidContent
        }

        // Remove optional #EXTM3U header
        if let first = lines.first, first.hasPrefix("#EXTM3U") {
            lines.removeFirst()
        }

        var channels: [Channel] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1

            guard line.hasPrefix("#EXTINF:") else { continue }

            // Find the next non-empty, non-comment line as the stream URL
            var streamLine: String?
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                index += 1
                if candidate.isEmpty || candidate.hasPrefix("#") { continue }
                streamLine = candidate
                break
            }

            guard let urlString = streamLine, !urlString.isEmpty else { continue }
            guard let streamURL = URL(string: urlString) else {
                throw M3UParserError.invalidURL(urlString)
            }

            let name = Self.parseName(from: line)
            let attrs = Self.parseAttributes(from: line)

            let logoURL = attrs["tvg-logo"].flatMap { URL(string: $0) }
            let groupTitle = attrs["group-title"] ?? "Uncategorized"
            let epgId = attrs["tvg-id"]

            let contentType = Self.detectContentType(name: name, groupTitle: groupTitle)

            let channel = Channel(
                name: name,
                streamURL: streamURL,
                logoURL: logoURL,
                groupTitle: groupTitle,
                epgId: epgId.flatMap { $0.isEmpty ? nil : $0 },
                contentType: contentType
            )
            channels.append(channel)
        }

        return channels
    }

    /// Reads an M3U file from `url` and parses it.
    ///
    /// - Parameter url: File URL to read from.
    /// - Returns: Parsed channels.
    /// - Throws: File read errors or `M3UParserError`.
    public static func parse(url: URL) throws -> [Channel] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(content: content)
    }

    // MARK: - Private helpers

    /// Extracts the channel name from an `#EXTINF` line (text after the last comma).
    private static func parseName(from extinf: String) -> String {
        guard let commaRange = extinf.range(of: ",", options: .backwards) else {
            return "Unknown"
        }
        let name = String(extinf[commaRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Unknown" : name
    }

    /// Parses `key="value"` attribute pairs from an `#EXTINF` line.
    private static func parseAttributes(from extinf: String) -> [String: String] {
        var attrs: [String: String] = [:]

        // Match key="value" pairs
        let pattern = #"([\w-]+)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return attrs }

        let range = NSRange(extinf.startIndex..., in: extinf)
        let matches = regex.matches(in: extinf, range: range)

        for match in matches {
            guard match.numberOfRanges == 3,
                  let keyRange = Range(match.range(at: 1), in: extinf),
                  let valRange = Range(match.range(at: 2), in: extinf)
            else { continue }

            attrs[String(extinf[keyRange])] = String(extinf[valRange])
        }

        return attrs
    }

    /// Detects content type based on channel name and group title.
    private static func detectContentType(name: String, groupTitle: String) -> ContentType {
        let lowercasedName = name.lowercased()
        let lowercasedGroup = groupTitle.lowercased()

        // Check group title first (most reliable)
        if lowercasedGroup.contains("series") || lowercasedGroup.contains("tv shows") || lowercasedGroup.contains("tvshows") {
            return .series
        }
        if lowercasedGroup.contains("movie") || lowercasedGroup.contains("vod") || lowercasedGroup.contains("films") {
            return .movie
        }

        // Check name patterns for series (S01E01, season/episode indicators)
        let seriesPatterns = [
            #"s\d{1,2}e\d{1,2}"#,           // S01E01, s1e1
            #"season\s*\d+"#,                // Season 1, season 01
            #"\d{1,2}x\d{1,2}"#,            // 1x01
            #"episode\s*\d+"#                // Episode 1
        ]

        for pattern in seriesPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowercasedName.startIndex..., in: lowercasedName)
                if regex.firstMatch(in: lowercasedName, range: range) != nil {
                    return .series
                }
            }
        }

        // Check for movie year patterns (e.g., "Movie Title (2024)")
        let movieYearPattern = #"\(\d{4}\)"#
        if let regex = try? NSRegularExpression(pattern: movieYearPattern) {
            let range = NSRange(lowercasedName.startIndex..., in: lowercasedName)
            if regex.firstMatch(in: lowercasedName, range: range) != nil {
                return .movie
            }
        }

        // Default to live TV
        return .liveTV
    }

    /// Parses episode information from a channel name.
    /// Returns (seriesName, season, episode, title) if detected, nil otherwise.
    public static func parseEpisodeInfo(from name: String) -> (seriesName: String, season: Int, episode: Int, title: String?)? {
        let patterns = [
            #"^(.+?)\s+s(\d{1,2})e(\d{1,2})(?:\s+-\s+(.+))?$"#,  // "Series Name S01E01 - Title"
            #"^(.+?)\s+(\d{1,2})x(\d{1,2})(?:\s+-\s+(.+))?$"#,   // "Series Name 1x01 - Title"
            #"^(.+?)\s+season\s*(\d+)\s+episode\s*(\d+)(?:\s+-\s+(.+))?$"#  // "Series Name Season 1 Episode 1 - Title"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(name.startIndex..., in: name)
            guard let match = regex.firstMatch(in: name, range: range) else { continue }

            guard match.numberOfRanges >= 4,
                  let seriesRange = Range(match.range(at: 1), in: name),
                  let seasonRange = Range(match.range(at: 2), in: name),
                  let episodeRange = Range(match.range(at: 3), in: name)
            else { continue }

            let seriesName = String(name[seriesRange]).trimmingCharacters(in: .whitespaces)
            guard let season = Int(name[seasonRange]),
                  let episode = Int(name[episodeRange])
            else { continue }

            var title: String?
            if match.numberOfRanges >= 5, match.range(at: 4).location != NSNotFound,
               let titleRange = Range(match.range(at: 4), in: name) {
                title = String(name[titleRange]).trimmingCharacters(in: .whitespaces)
            }

            return (seriesName, season, episode, title)
        }

        return nil
    }

    /// Parses movie information from a channel name.
    /// Returns (title, year) if detected, nil otherwise.
    public static func parseMovieInfo(from name: String) -> (title: String, year: Int?)? {
        // Pattern: "Movie Title (2024)"
        let pattern = #"^(.+?)\s*\((\d{4})\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(name.startIndex..., in: name)
        guard let match = regex.firstMatch(in: name, range: range) else { return nil }

        guard match.numberOfRanges >= 3,
              let titleRange = Range(match.range(at: 1), in: name),
              let yearRange = Range(match.range(at: 2), in: name)
        else { return nil }

        let title = String(name[titleRange]).trimmingCharacters(in: .whitespaces)
        let year = Int(name[yearRange])

        return (title, year)
    }
}
