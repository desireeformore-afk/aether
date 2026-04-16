import Foundation

/// Represents a subtitle track from OpenSubtitles.
public struct SubtitleTrack: Identifiable, Sendable, Hashable {
    public let id: String           // opensubtitles file_id
    public let language: String     // e.g. "pl", "en"
    public let languageName: String
    public let downloadURL: URL?    // filled after /download call
    public let rating: Double
    public let fileSize: Int

    public init(
        id: String,
        language: String,
        languageName: String,
        downloadURL: URL? = nil,
        rating: Double = 0,
        fileSize: Int = 0
    ) {
        self.id = id
        self.language = language
        self.languageName = languageName
        self.downloadURL = downloadURL
        self.rating = rating
        self.fileSize = fileSize
    }
}
