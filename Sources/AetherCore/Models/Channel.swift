import Foundation

/// A channel in an IPTV playlist.
///
/// Represents a single IPTV channel with its stream URL, metadata, and EPG information.
///
/// ## Topics
///
/// ### Creating a Channel
/// - ``init(id:name:streamURL:logoURL:groupTitle:epgId:)``
///
/// ### Channel Properties
/// - ``id``
/// - ``name``
/// - ``streamURL``
/// - ``logoURL``
/// - ``groupTitle``
/// - ``epgId``
public struct Channel: Identifiable, Sendable, Hashable {
    /// Unique identifier for the channel.
    public let id: UUID

    /// Display name of the channel.
    public var name: String

    /// URL of the stream (HTTP/HTTPS/HLS).
    public var streamURL: URL

    /// Optional URL for the channel logo image.
    public var logoURL: URL?

    /// Category or group this channel belongs to (e.g., "News", "Sports").
    public var groupTitle: String

    /// EPG identifier for matching with electronic program guide data.
    public var epgId: String?

    /// Age rating for parental control filtering.
    public let ageRating: AgeRating?

    /// Creates a new channel.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - name: Display name of the channel.
    ///   - streamURL: URL of the stream.
    ///   - logoURL: Optional logo image URL.
    ///   - groupTitle: Category or group. Defaults to "Uncategorized".
    ///   - epgId: EPG identifier for program guide matching.
    ///   - ageRating: Age rating for parental controls.
    public init(
        id: UUID = UUID(),
        name: String,
        streamURL: URL,
        logoURL: URL? = nil,
        groupTitle: String = "Uncategorized",
        epgId: String? = nil,
        ageRating: AgeRating? = nil
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.logoURL = logoURL
        self.groupTitle = groupTitle
        self.epgId = epgId
        self.ageRating = ageRating
    }
}
