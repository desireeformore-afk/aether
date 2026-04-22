import Foundation
import SwiftData

/// Lightweight SwiftData record for a favorited item (channel, VOD, or series).
@Model
public final class FavoriteRecord {
    @Attribute(.unique) public var channelID: UUID
    public var channelName: String
    public var streamURLString: String
    public var logoURLString: String?
    public var groupTitle: String
    public var epgId: String?
    public var addedAt: Date
    /// Content type: "channel", "vod", or "series". Default "channel" for existing records.
    public var contentType: String

    public init(channel: Channel) {
        self.channelID = channel.id
        self.channelName = channel.name
        self.streamURLString = channel.streamURL.absoluteString
        self.logoURLString = channel.logoURL?.absoluteString
        self.groupTitle = channel.groupTitle
        self.epgId = channel.epgId
        self.addedAt = Date()
        self.contentType = "channel"
    }

    public init(itemID: UUID, name: String, streamURLString: String, posterURLString: String?, contentType: String) {
        self.channelID = itemID
        self.channelName = name
        self.streamURLString = streamURLString
        self.logoURLString = posterURLString
        self.groupTitle = contentType
        self.epgId = nil
        self.addedAt = Date()
        self.contentType = contentType
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
