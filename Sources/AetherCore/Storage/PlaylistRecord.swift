import Foundation
import SwiftData

/// Source type of a playlist.
public enum PlaylistType: String, Codable, Sendable, CaseIterable {
    case m3u = "m3u"
    case xtream = "xtream"
}

/// Persistent SwiftData model for a stored playlist.
/// NOTE: Channel data is NOT stored in SwiftData — use `ChannelCache` instead.
@Model
public final class PlaylistRecord {
    public var id: UUID
    public var name: String
    /// M3U URL string (used when `playlistType == .m3u`).
    public var urlString: String
    public var lastRefreshed: Date?
    /// Display order in the sidebar.
    public var sortIndex: Int
    /// Raw value of `PlaylistType`.
    public var playlistTypeRaw: String
    // Xtream Codes credentials (used when `playlistType == .xtream`)
    public var xstreamHost: String?
    public var xstreamUsername: String?
    public var xstreamPassword: String?
    /// Optional XMLTV EPG URL override for this playlist.
    public var epgURLString: String?

    public init(
        id: UUID = UUID(),
        name: String,
        urlString: String = "",
        lastRefreshed: Date? = nil,
        sortIndex: Int = 0,
        playlistType: PlaylistType = .m3u,
        xstreamHost: String? = nil,
        xstreamUsername: String? = nil,
        xstreamPassword: String? = nil,
        epgURLString: String? = nil
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.lastRefreshed = lastRefreshed
        self.sortIndex = sortIndex
        self.playlistTypeRaw = playlistType.rawValue
        self.xstreamHost = xstreamHost
        self.xstreamUsername = xstreamUsername
        self.xstreamPassword = xstreamPassword
        self.epgURLString = epgURLString
    }

    public var playlistType: PlaylistType {
        get { PlaylistType(rawValue: playlistTypeRaw) ?? .m3u }
        set { playlistTypeRaw = newValue.rawValue }
    }

    public var url: URL? { URL(string: urlString) }
    public var epgURL: URL? { epgURLString.flatMap(URL.init(string:)) }

    /// Xtream Codes credentials, if configured.
    /// Password is loaded from Keychain first; falls back to the SwiftData field for existing records.
    public var xstreamCredentials: XstreamCredentials? {
        guard playlistType == .xtream,
              let host = xstreamHost, !host.isEmpty,
              let user = xstreamUsername, !user.isEmpty,
              let baseURL = URL(string: host) else { return nil }
        let pass = KeychainService.load(for: id.uuidString) ?? xstreamPassword ?? ""
        guard !pass.isEmpty else { return nil }
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
        return creds.baseURL
            .appendingPathComponent("xmltv.php")
            .appending(queryItems: [
                URLQueryItem(name: "username", value: creds.username),
                URLQueryItem(name: "password", value: creds.password)
            ])
    }
}
