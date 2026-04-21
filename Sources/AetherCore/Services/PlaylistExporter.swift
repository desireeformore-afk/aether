import Foundation

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

    /// Exports the given channels to an M3U file at the specified URL.
    @MainActor
    public static func export(to url: URL, channels: [Channel]) async throws {
        guard !channels.isEmpty else {
            throw ExportError.noChannels
        }

        var m3uContent = "#EXTM3U\n"

        for channel in channels {
            m3uContent += "#EXTINF:-1"

            let groupTitle = channel.groupTitle
            if !groupTitle.isEmpty {
                m3uContent += " group-title=\"\(groupTitle)\""
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
