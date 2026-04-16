import Foundation
import SwiftData

/// Persistent SwiftData model for a stored channel.
@Model
public final class ChannelRecord {
    public var id: UUID
    public var name: String
    public var streamURLString: String
    public var logoURLString: String?
    public var groupTitle: String
    public var epgId: String?
    public var sortIndex: Int
    public var playlist: PlaylistRecord?

    public init(
        id: UUID = UUID(),
        name: String,
        streamURLString: String,
        logoURLString: String? = nil,
        groupTitle: String = "Uncategorized",
        epgId: String? = nil,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.streamURLString = streamURLString
        self.logoURLString = logoURLString
        self.groupTitle = groupTitle
        self.epgId = epgId
        self.sortIndex = sortIndex
    }

    /// Converts to the value-type `Channel` used throughout AetherCore.
    public func toChannel() -> Channel? {
        guard let url = URL(string: streamURLString) else { return nil }
        return Channel(
            id: id,
            name: name,
            streamURL: url,
            logoURL: logoURLString.flatMap { URL(string: $0) },
            groupTitle: groupTitle,
            epgId: epgId
        )
    }
}
