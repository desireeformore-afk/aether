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
public struct M3UParser: Sendable {

    /// Parses M3U content from a `String` and returns an array of `Channel`.
    ///
    /// - Parameter content: Raw M3U playlist text.
    /// - Returns: Parsed channels in order of appearance.
    /// - Throws: `M3UParserError` on unrecoverable format errors.
    public static func parse(content: String) throws -> [Channel] {
        // Strip UTF-8 BOM if present
        var text = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content

        // Normalize line endings
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")

        var lines = text.components(separatedBy: "\n")

        // Validate: must contain at least one #EXTINF or #EXTM3U line
        let hasM3UContent = lines.contains { $0.hasPrefix("#EXTM3U") || $0.hasPrefix("#EXTINF:") }
        guard hasM3UContent else {
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

            let channel = Channel(
                name: name,
                streamURL: streamURL,
                logoURL: logoURL,
                groupTitle: groupTitle,
                epgId: epgId.flatMap { $0.isEmpty ? nil : $0 }
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
}
