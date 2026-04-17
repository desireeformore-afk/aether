import Foundation

public struct SubtitleCue: Sendable {
    public let start: TimeInterval   // seconds
    public let end: TimeInterval
    public let text: String
}

public enum SRTParser {
    /// Parses SRT or WebVTT subtitle text into an array of `SubtitleCue`.
    public static func parse(_ content: String) -> [SubtitleCue] {
        // Normalize line endings
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
                                .replacingOccurrences(of: "\r", with: "\n")
        // Strip BOM
        let stripped = normalized.hasPrefix("\u{FEFF}")
            ? String(normalized.dropFirst()) : normalized

        // Remove WebVTT header if present
        var text = stripped
        if text.hasPrefix("WEBVTT") {
            text = text.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
        }

        var cues: [SubtitleCue] = []
        let blocks = text.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                            .components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }

            // Find timecode line (may be preceded by index number)
            var timeLine = lines[0]
            var textStart = 1
            if !timeLine.contains("-->") && lines.count > 1 {
                timeLine = lines[1]
                textStart = 2
            }
            guard timeLine.contains("-->"),
                  let (start, end) = parseTimecode(timeLine) else { continue }

            let cueText = lines[textStart...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cueText.isEmpty else { continue }

            cues.append(SubtitleCue(start: start, end: end, text: cueText))
        }
        return cues
    }

    private static func parseTimecode(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2,
              let s = parseTime(parts[0].trimmingCharacters(in: .whitespaces)),
              let e = parseTime(parts[1].components(separatedBy: " ").first ?? "") else { return nil }
        return (s, e)
    }

    private static func parseTime(_ s: String) -> TimeInterval? {
        // Accepts HH:MM:SS,mmm  HH:MM:SS.mmm  MM:SS.mmm
        let clean = s.replacingOccurrences(of: ",", with: ".")
        let parts = clean.components(separatedBy: ":")
        if parts.count == 3,
           let h = Double(parts[0]), let m = Double(parts[1]), let sec = Double(parts[2]) {
            return h * 3600 + m * 60 + sec
        } else if parts.count == 2,
                  let m = Double(parts[0]), let sec = Double(parts[1]) {
            return m * 60 + sec
        }
        return nil
    }
}
