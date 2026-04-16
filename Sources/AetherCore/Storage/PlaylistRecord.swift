import Foundation
import SwiftData

/// Source type of a playlist.
public enum PlaylistType: String, Codable, Sendable, CaseIterable {
    case m3u = "m3u"
    case xtream = "xtream"
}

/// Persistent SwiftData model for a stored playlist.
@Model
public final class PlaylistRecord {
    public var id: UUID
    public var name: String
    /// M3U URL string (used when `playlistType == .m3u`).
    public var urlString: String
    public var lastRefreshed: Date?
    /// Raw value of `PlaylistType`.
    public var playlistTypeRaw: String
    // Xtream Codes credentials (used when `playlistType == .xtream`)
    public var xstreamHost: String?
    public var xstreamUsername: String?
    public var xstreamPassword: String?
    /// Optional XMLTV EPG URL override for this playlist.
    public var epgURLString: String?

    @Relationship(deleteRule: .cascade, inverse: \ChannelRecord.playlist)
    public var channels: [ChannelRecord]

    public init(
        id: UUID = UUID(),
        name: String,
        urlString: String = "",
        lastRefreshed: Date? = nil,
        playlistType: PlaylistType = .m3u,
        xstreamHost: String? = nil,
        xstreamUsername: String? = nil,
        xstreamPassword: String? = nil,
        epgURLString: String? = nil,
        channels: [ChannelRecord] = []
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.lastRefreshed = lastRefreshed
        self.playlistTypeRaw = playlistType.rawValue
        self.xstreamHost = xstreamHost
        self.xstreamUsername = xstreamUsername
        self.xstreamPassword = xstreamPassword
        self.epgURLString = epgURLString
        self.channels = channels
    }

    public var playlistType: PlaylistType {
        get { PlaylistType(rawValue: playlistTypeRaw) ?? .m3u }
        set { playlistTypeRaw = newValue.rawValue }
    }

    public var url: URL? { URL(string: urlString) }
    public var epgURL: URL? { epgURLString.flatMap(URL.init(string:)) }

    /// Xtream Codes credentials, if configured.
    public var xstreamCredentials: XstreamCredentials? {
        guard playlistType == .xtream,
              let host = xstreamHost, !host.isEmpty,
              let user = xstreamUsername, !user.isEmpty,
              let pass = xstreamPassword,
              let baseURL = URL(string: host) else { return nil }
        return XstreamCredentials(baseURL: baseURL, username: user, password: pass)
    }

    /// M3U URL for Xtream Codes panels (used when type == .xtream).
    public var xtreamM3UURL: URL? {
        guard let creds = xstreamCredentials else { return nil }
        return creds.baseURL
            .appendingPathComponent("get.php")
            .appending(queryItems: [
                URLQueryItem(name: "username", value: creds.username),
                URLQueryItem(name: "password", value: creds.password),
                URLQueryItem(name: "type", value: "m3u_plus"),
                URLQueryItem(name: "output", value: "ts")
            ])
    }

    /// The effective M3U URL to fetch, regardless of playlist type.
    public var effectiveURL: URL? {
        switch playlistType {
        case .m3u:    return url
        case .xtream: return xtreamM3UURL
        }
    }

    /// The effective EPG (XMLTV) URL, if any.
    public var effectiveEPGURL: URL? {
        if let epg = epgURL { return epg }
        guard let creds = xstreamCredentials else { return nil }
        // Xtream panels expose XMLTV at /xmltv.php
        return creds.baseURL
            .appendingPathComponent("xmltv.php")
            .appending(queryItems: [
                URLQueryItem(name: "username", value: creds.username),
                URLQueryItem(name: "password", value: creds.password)
            ])
    }
}
