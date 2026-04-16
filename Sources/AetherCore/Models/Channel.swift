import Foundation

/// A channel in an IPTV playlist.
public struct Channel: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var streamURL: URL
    public var logoURL: URL?
    public var groupTitle: String
    public var epgId: String?

    public init(
        id: UUID = UUID(),
        name: String,
        streamURL: URL,
        logoURL: URL? = nil,
        groupTitle: String = "Uncategorized",
        epgId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.logoURL = logoURL
        self.groupTitle = groupTitle
        self.epgId = epgId
    }
}
