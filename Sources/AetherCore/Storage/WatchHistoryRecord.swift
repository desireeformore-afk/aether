import Foundation
import SwiftData

/// Lightweight SwiftData record for a watch history entry.
@Model
public final class WatchHistoryRecord {
    public var id: UUID
    public var channelID: UUID
    public var channelName: String
    public var streamURLString: String
    public var logoURLString: String?
    public var groupTitle: String
    public var epgId: String?
    public var watchedAt: Date
    public var durationSeconds: Int

    public init(channel: Channel, watchedAt: Date = .now, durationSeconds: Int = 0) {
        self.id = UUID()
        self.channelID = channel.id
        self.channelName = channel.name
        self.streamURLString = channel.streamURL.absoluteString
        self.logoURLString = channel.logoURL?.absoluteString
        self.groupTitle = channel.groupTitle
        self.epgId = channel.epgId
        self.watchedAt = watchedAt
        self.durationSeconds = durationSeconds
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
