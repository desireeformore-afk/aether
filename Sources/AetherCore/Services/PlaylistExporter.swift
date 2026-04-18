import Foundation
import SwiftData

/// Exports playlists to M3U format.
public enum PlaylistExporter {

    public enum ExportError: Error, LocalizedError {
        case noChannels
        case writeFailure(Error)

        public var errorDescription: String? {
            switch self {
            case .noChannels:
                return "No channels to export"
            case .writeFailure(let error):
                return "Failed to write file: \(error.localizedDescription)"
            }
        }
    }

    /// Exports all channels from the current playlist to an M3U file.
    @MainActor
    public static func export(to url: URL) async throws {
        // For now, we'll export a basic M3U structure
        // In a real implementation, you'd fetch channels from SwiftData

        var m3uContent = "#EXTM3U\n"

        // TODO: Fetch channels from SwiftData context
        // For now, create a placeholder implementation
        let channels: [Channel] = []

        guard !channels.isEmpty else {
            throw ExportError.noChannels
        }

        for channel in channels {
            m3uContent += "#EXTINF:-1"

            if !channel.groupTitle.isEmpty {
                m3uContent += " group-title=\"\(channel.groupTitle)\""
            }

            if let logoURL = channel.logoURL {
                m3uContent += " tvg-logo=\"\(logoURL.absoluteString)\""
            }

            if let epgId = channel.epgId, !epgId.isEmpty {
                m3uContent += " tvg-id=\"\(epgId)\""
            }

            m3uContent += ",\(channel.name)\n"
            m3uContent += "\(channel.streamURL.absoluteString)\n"
        }

        do {
            try m3uContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailure(error)
        }
    }
}
