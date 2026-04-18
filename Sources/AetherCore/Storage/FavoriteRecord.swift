import Foundation
import SwiftData

/// Lightweight SwiftData record for a favorited channel.
@Model
public final class FavoriteRecord {
    @Attribute(.unique) public var channelID: UUID
    public var channelName: String
    public var streamURLString: String
    public var logoURLString: String?
    public var groupTitle: String
    public var epgId: String?
    public var addedAt: Date

    public init(channel: Channel) {
        self.channelID = channel.id
        self.channelName = channel.name
        self.streamURLString = channel.streamURL.absoluteString
        self.logoURLString = channel.logoURL?.absoluteString
        self.groupTitle = channel.groupTitle
        self.epgId = channel.epgId
        self.addedAt = Date()
    }

    public func toChannel() -> Channel? {
        guard let url = URL(string: streamURLString) else { return nil }
        return Channel(
            id: channelID,
            name: channelName,
            streamURL: url,
            logoURL: logoURLString.flatMap { URL(string: $0) },
            groupTitle: groupTitle,
            epgId: epgId
        )
    }
}
