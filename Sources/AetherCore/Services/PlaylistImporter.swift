import Foundation
import SwiftData

/// Imports M3U playlists into the app.
public enum PlaylistImporter {

    public enum ImportError: Error, LocalizedError {
        case readFailure(Error)
        case invalidFormat
        case noChannels

        public var errorDescription: String? {
            switch self {
            case .readFailure(let error):
                return "Failed to read file: \(error.localizedDescription)"
            case .invalidFormat:
                return "Invalid M3U format"
            case .noChannels:
                return "No valid channels found in file"
            }
        }
    }

    /// Imports channels from an M3U file.
    /// Returns the number of channels imported.
    @MainActor
    public static func `import`(from url: URL) async throws -> Int {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ImportError.readFailure(error)
        }

        guard content.hasPrefix("#EXTM3U") || content.contains("#EXTINF:") else {
            throw ImportError.invalidFormat
        }

        let channels = M3UParser.parse(content: content)

        guard !channels.isEmpty else {
            throw ImportError.noChannels
        }

        // TODO: Save channels to SwiftData
        // For now, just return the count
        return channels.count
    }
}
