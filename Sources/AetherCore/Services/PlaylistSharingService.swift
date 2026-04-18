import Foundation
import CoreImage

/// Service for managing playlist sharing functionality
@MainActor
public final class PlaylistSharingService: ObservableObject {
    @Published public private(set) var sharedPlaylists: [ShareablePlaylist] = []
    @Published public private(set) var shareStats: [String: PlaylistShareStats] = [:]

    private let storageKey = "aether.shared_playlists"
    private let statsKey = "aether.share_stats"

    public init() {
        loadSharedPlaylists()
        loadShareStats()
    }

    // MARK: - Share Creation

    /// Create a shareable link for a playlist
    public func createShareLink(
        for playlist: Playlist,
        channelCount: Int,
        isPublic: Bool = false,
        expiresIn: TimeInterval? = nil,
        description: String? = nil,
        tags: [String] = []
    ) -> ShareablePlaylist {
        let expiresAt = expiresIn.map { Date().addingTimeInterval($0) }

        let shareable = ShareablePlaylist(
            name: playlist.name,
            url: playlist.url,
            type: playlist.type,
            channelCount: channelCount,
            expiresAt: expiresAt,
            isPublic: isPublic,
            description: description,
            tags: tags
        )

        sharedPlaylists.append(shareable)
        shareStats[shareable.shareCode] = PlaylistShareStats(shareCode: shareable.shareCode)

        saveSharedPlaylists()
        saveShareStats()

        return shareable
    }

    /// Generate QR code image for a shareable playlist
    public func generateQRCode(for shareable: ShareablePlaylist, size: CGSize = CGSize(width: 512, height: 512)) -> CGImage? {
        guard let data = shareable.generateQRCodeData() else { return nil }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter?.outputImage else { return nil }

        let scaleX = size.width / outputImage.extent.width
        let scaleY = size.height / outputImage.extent.height
        let scale = min(scaleX, scaleY)

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }

    // MARK: - Share Import

    /// Import a playlist from a share code
    public func importFromShareCode(_ shareCode: String) async throws -> Playlist {
        guard let shareable = await fetchSharedPlaylist(shareCode: shareCode) else {
            throw SharingError.shareNotFound
        }

        guard !shareable.isExpired else {
            throw SharingError.shareExpired
        }

        // Update stats
        if var stats = shareStats[shareCode] {
            stats.importCount += 1
            stats.lastAccessed = Date()
            shareStats[shareCode] = stats
            saveShareStats()
        }

        // Create playlist from shareable
        return Playlist(
            name: shareable.name,
            url: shareable.url,
            type: shareable.type
        )
    }

    /// Import a playlist from a share URL
    public func importFromURL(_ url: URL) async throws -> Playlist {
        let shareCode = extractShareCode(from: url)
        return try await importFromShareCode(shareCode)
    }

    // MARK: - Share Management

    /// Delete a shared playlist
    public func deleteShare(_ shareable: ShareablePlaylist) {
        sharedPlaylists.removeAll { $0.id == shareable.id }
        shareStats.removeValue(forKey: shareable.shareCode)
        saveSharedPlaylists()
        saveShareStats()
    }

    /// Update share settings
    public func updateShare(_ shareable: ShareablePlaylist) {
        if let index = sharedPlaylists.firstIndex(where: { $0.id == shareable.id }) {
            sharedPlaylists[index] = shareable
            saveSharedPlaylists()
        }
    }

    /// Get statistics for a share
    public func getStats(for shareCode: String) -> PlaylistShareStats? {
        return shareStats[shareCode]
    }

    /// Record a view for a shared playlist
    public func recordView(for shareCode: String) {
        if var stats = shareStats[shareCode] {
            stats.viewCount += 1
            stats.lastAccessed = Date()
            shareStats[shareCode] = stats
            saveShareStats()
        }
    }

    // MARK: - Public Directory

    /// Get all public playlists
    public func getPublicPlaylists() -> [ShareablePlaylist] {
        return sharedPlaylists.filter { $0.isPublic && !$0.isExpired }
    }

    /// Search public playlists
    public func searchPublicPlaylists(query: String) -> [ShareablePlaylist] {
        let lowercaseQuery = query.lowercased()
        return getPublicPlaylists().filter { playlist in
            playlist.name.lowercased().contains(lowercaseQuery) ||
            playlist.description?.lowercased().contains(lowercaseQuery) == true ||
            playlist.tags.contains { $0.lowercased().contains(lowercaseQuery) }
        }
    }

    /// Get public playlists by tag
    public func getPublicPlaylists(withTag tag: String) -> [ShareablePlaylist] {
        return getPublicPlaylists().filter { $0.tags.contains(tag) }
    }

    // MARK: - Share Link Parsing

    private func extractShareCode(from url: URL) -> String {
        if url.scheme == "aether" {
            // aether://share/ABCD1234
            return url.lastPathComponent
        } else {
            // https://aether.app/share/ABCD1234
            return url.lastPathComponent
        }
    }

    private func fetchSharedPlaylist(shareCode: String) async -> ShareablePlaylist? {
        // In a real app, this would fetch from a server
        // For now, check local storage
        return sharedPlaylists.first { $0.shareCode == shareCode }
    }

    // MARK: - Persistence

    private func loadSharedPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let playlists = try? JSONDecoder().decode([ShareablePlaylist].self, from: data) else {
            return
        }
        sharedPlaylists = playlists
    }

    private func saveSharedPlaylists() {
        guard let data = try? JSONEncoder().encode(sharedPlaylists) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadShareStats() {
        guard let data = UserDefaults.standard.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode([String: PlaylistShareStats].self, from: data) else {
            return
        }
        shareStats = stats
    }

    private func saveShareStats() {
        guard let data = try? JSONEncoder().encode(shareStats) else { return }
        UserDefaults.standard.set(data, forKey: statsKey)
    }
}

// MARK: - Errors

public enum SharingError: Error, LocalizedError {
    case shareNotFound
    case shareExpired
    case invalidShareCode
    case networkError

    public var errorDescription: String? {
        switch self {
        case .shareNotFound:
            return "Shared playlist not found"
        case .shareExpired:
            return "This share link has expired"
        case .invalidShareCode:
            return "Invalid share code"
        case .networkError:
            return "Network error occurred"
        }
    }
}
