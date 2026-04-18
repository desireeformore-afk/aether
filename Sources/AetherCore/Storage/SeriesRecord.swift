import Foundation
import SwiftData

/// SwiftData record for storing series metadata and preferences.
@Model
public final class SeriesRecord {
    /// Unique identifier for the series.
    public var id: UUID

    /// Name of the series.
    public var name: String

    /// Optional poster URL string.
    public var posterURLString: String?

    /// Whether this series is marked as favorite.
    public var isFavorite: Bool

    /// Custom sort order preference.
    public var sortOrder: Int

    /// Last accessed timestamp.
    public var lastAccessedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        posterURLString: String? = nil,
        isFavorite: Bool = false,
        sortOrder: Int = 0,
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.posterURLString = posterURLString
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
        self.lastAccessedAt = lastAccessedAt
    }

    public var posterURL: URL? {
        posterURLString.flatMap { URL(string: $0) }
    }
}
