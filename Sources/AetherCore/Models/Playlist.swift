import Foundation

/// An IPTV playlist containing a collection of channels.
public struct Playlist: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var type: PlaylistType
    public var channels: [Channel]

    public init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        type: PlaylistType = .m3u,
        channels: [Channel] = []
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.type = type
        self.channels = channels
    }
}
