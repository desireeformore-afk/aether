import Foundation

/// Downloads and caches M3U playlists, then parses them into `[Channel]`.
public actor PlaylistService {

    private let cacheDirectory: URL

    public init(cacheDirectory: URL? = nil) {
        if let dir = cacheDirectory {
            self.cacheDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = appSupport
                .appendingPathComponent("Aether", isDirectory: true)
                .appendingPathComponent("PlaylistCache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.cacheDirectory, withIntermediateDirectories: true
        )
    }

    /// Fetches an M3U playlist from `url`, caches it locally, and returns parsed channels.
    ///
    /// - Parameters:
    ///   - url: Remote or local URL of the M3U file.
    ///   - forceRefresh: When `true`, ignores cached content.
    /// - Returns: Parsed array of `Channel`.
    public func fetchChannels(from url: URL, forceRefresh: Bool = false) async throws -> [Channel] {
        let cacheFile = cacheURL(for: url)

        if !forceRefresh, FileManager.default.fileExists(atPath: cacheFile.path) {
            let cached = try String(contentsOf: cacheFile, encoding: .utf8)
            return try M3UParser.parse(content: cached)
        }

        let content: String
        if url.isFileURL {
            content = try String(contentsOf: url, encoding: .utf8)
        } else {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw PlaylistServiceError.httpError(
                    (response as? HTTPURLResponse)?.statusCode ?? -1
                )
            }
            guard let text = String(data: data, encoding: .utf8)
                          ?? String(data: data, encoding: .isoLatin1) else {
                throw PlaylistServiceError.decodingFailed
            }
            content = text
        }

        // Persist to cache
        try content.write(to: cacheFile, atomically: true, encoding: .utf8)

        return try M3UParser.parse(content: content)
    }

    /// Removes cached data for a given URL.
    public func clearCache(for url: URL) {
        try? FileManager.default.removeItem(at: cacheURL(for: url))
    }

    /// Removes all cached playlists.
    public func clearAllCaches() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil
        )) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: - Private

    private func cacheURL(for url: URL) -> URL {
        let hash = abs(url.absoluteString.hashValue)
        return cacheDirectory.appendingPathComponent("\(hash).m3u")
    }
}

/// Errors thrown by `PlaylistService`.
public enum PlaylistServiceError: Error, Sendable {
    case httpError(Int)
    case decodingFailed
}
