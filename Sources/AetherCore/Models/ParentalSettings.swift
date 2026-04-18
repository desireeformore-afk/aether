import Foundation

/// Parental control settings.
///
/// Stores configuration for content restrictions and PIN protection.
public struct ParentalSettings: Codable, Sendable {
    /// Whether parental controls are enabled.
    public var isEnabled: Bool

    /// Encrypted PIN hash (SHA-256).
    public var pinHash: String?

    /// Maximum allowed age rating.
    public var maxAgeRating: AgeRating

    /// List of channel IDs that are locked.
    public var lockedChannelIds: Set<UUID>

    /// Time-based restrictions (hour in 24h format).
    public var timeRestrictions: [TimeRestriction]

    /// Whether to require PIN for settings changes.
    public var requirePINForSettings: Bool

    public init(
        isEnabled: Bool = false,
        pinHash: String? = nil,
        maxAgeRating: AgeRating = .nc17,
        lockedChannelIds: Set<UUID> = [],
        timeRestrictions: [TimeRestriction] = [],
        requirePINForSettings: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.pinHash = pinHash
        self.maxAgeRating = maxAgeRating
        self.lockedChannelIds = lockedChannelIds
        self.timeRestrictions = timeRestrictions
        self.requirePINForSettings = requirePINForSettings
    }
}

/// Time-based content restriction.
public struct TimeRestriction: Codable, Sendable, Identifiable {
    public let id: UUID

    /// Start hour (0-23).
    public var startHour: Int

    /// End hour (0-23).
    public var endHour: Int

    /// Maximum age rating during this time period.
    public var maxAgeRating: AgeRating

    /// Days of week this restriction applies (1=Sunday, 7=Saturday).
    public var daysOfWeek: Set<Int>

    public init(
        id: UUID = UUID(),
        startHour: Int,
        endHour: Int,
        maxAgeRating: AgeRating,
        daysOfWeek: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    ) {
        self.id = id
        self.startHour = startHour
        self.endHour = endHour
        self.maxAgeRating = maxAgeRating
        self.daysOfWeek = daysOfWeek
    }

    /// Check if this restriction is active at the given date.
    public func isActive(at date: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)

        guard daysOfWeek.contains(weekday) else { return false }

        if startHour <= endHour {
            return hour >= startHour && hour < endHour
        } else {
            // Crosses midnight
            return hour >= startHour || hour < endHour
        }
    }
}
