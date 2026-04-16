import Foundation
import SwiftData

/// Persistent SwiftData model for a stored playlist.
@Model
public final class PlaylistRecord {
    public var id: UUID
    public var name: String
    public var urlString: String
    public var lastRefreshed: Date?
    @Relationship(deleteRule: .cascade, inverse: \ChannelRecord.playlist)
    public var channels: [ChannelRecord]

    public init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        lastRefreshed: Date? = nil,
        channels: [ChannelRecord] = []
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.lastRefreshed = lastRefreshed
        self.channels = channels
    }

    public var url: URL? { URL(string: urlString) }
}
