import Foundation

/// Shareable playlist model for generating links and QR codes
public struct ShareablePlaylist: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let url: String
    public let type: PlaylistType
    public let channelCount: Int
    public let createdAt: Date
    public let expiresAt: Date?
    public let shareCode: String
    public var isPublic: Bool
    public var description: String?
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        url: String,
        type: PlaylistType,
        channelCount: Int,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        shareCode: String = ShareablePlaylist.generateShareCode(),
        isPublic: Bool = false,
        description: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.type = type
        self.channelCount = channelCount
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.shareCode = shareCode
        self.isPublic = isPublic
        self.description = description
        self.tags = tags
    }

    /// Generate a unique 8-character share code
    public static func generateShareCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Exclude ambiguous chars
        return String((0..<8).map { _ in characters.randomElement()! })
    }

    /// Generate shareable URL
    public var shareURL: URL {
        URL(string: "aether://share/\(shareCode)")!
    }

    /// Generate web shareable URL
    public var webShareURL: URL {
        URL(string: "https://aether.app/share/\(shareCode)")!
    }

    /// Check if share link has expired
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    /// Generate QR code data
    public func generateQRCodeData() -> Data? {
        return webShareURL.absoluteString.data(using: .utf8)
    }
}

/// Playlist share statistics
public struct PlaylistShareStats: Codable {
    public let shareCode: String
    public var viewCount: Int
    public var importCount: Int
    public var lastAccessed: Date?

    public init(shareCode: String, viewCount: Int = 0, importCount: Int = 0, lastAccessed: Date? = nil) {
        self.shareCode = shareCode
        self.viewCount = viewCount
        self.importCount = importCount
        self.lastAccessed = lastAccessed
    }
}
