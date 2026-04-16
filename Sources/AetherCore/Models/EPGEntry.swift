import Foundation

/// A single EPG programme entry from an XMLTV feed.
public struct EPGEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Channel ID as declared in the XMLTV feed (`channel` attribute on `<programme>`).
    public let channelID: String
    public let title: String
    public let description: String?
    public let start: Date
    public let end: Date
    public let category: String?
    public let iconURL: URL?

    public init(
        id: UUID = UUID(),
        channelID: String,
        title: String,
        description: String? = nil,
        start: Date,
        end: Date,
        category: String? = nil,
        iconURL: URL? = nil
    ) {
        self.id = id
        self.channelID = channelID
        self.title = title
        self.description = description
        self.start = start
        self.end = end
        self.category = category
        self.iconURL = iconURL
    }

    /// Whether this entry is currently airing at `date`.
    public func isOnAir(at date: Date = Date()) -> Bool {
        start <= date && date < end
    }

    /// Progress (0–1) of this programme at `date`.
    public func progress(at date: Date = Date()) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return max(0, min(1, date.timeIntervalSince(start) / total))
    }
}
