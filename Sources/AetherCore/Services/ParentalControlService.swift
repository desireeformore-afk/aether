import Foundation
import CryptoKit

/// Service for managing parental controls and content restrictions.
///
/// Handles PIN validation, content filtering, and time-based restrictions.
@MainActor
public final class ParentalControlService: ObservableObject {
    @Published public private(set) var settings: ParentalSettings
    @Published public private(set) var isUnlocked: Bool = false

    private let userDefaults: UserDefaults
    private let settingsKey = "aether.parentalControls.settings"
    private let unlockExpirationKey = "aether.parentalControls.unlockExpiration"

    /// Session unlock duration (30 minutes).
    private let sessionDuration: TimeInterval = 30 * 60

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load settings
        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(ParentalSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = ParentalSettings()
        }

        // Check if session is still valid
        if let expiration = userDefaults.object(forKey: unlockExpirationKey) as? Date,
           expiration > Date() {
            self.isUnlocked = true
        }
    }

    // MARK: - PIN Management

    /// Set up a new PIN.
    public func setupPIN(_ pin: String) throws {
        guard pin.count == 4, pin.allSatisfy({ $0.isNumber }) else {
            throw ParentalControlError.invalidPIN
        }

        settings.pinHash = hashPIN(pin)
        settings.isEnabled = true
        try saveSettings()
    }

    /// Validate PIN and unlock session.
    public func validatePIN(_ pin: String) -> Bool {
        guard let storedHash = settings.pinHash else { return false }

        let inputHash = hashPIN(pin)
        let isValid = inputHash == storedHash

        if isValid {
            unlockSession()
        }

        return isValid
    }

    /// Change existing PIN (requires current PIN).
    public func changePIN(current: String, new: String) throws {
        guard validatePIN(current) else {
            throw ParentalControlError.incorrectPIN
        }

        guard new.count == 4, new.allSatisfy({ $0.isNumber }) else {
            throw ParentalControlError.invalidPIN
        }

        settings.pinHash = hashPIN(new)
        try saveSettings()
    }

    /// Reset PIN (requires authentication through system).
    public func resetPIN() throws {
        settings.pinHash = nil
        settings.isEnabled = false
        isUnlocked = false
        userDefaults.removeObject(forKey: unlockExpirationKey)
        try saveSettings()
    }

    private func hashPIN(_ pin: String) -> String {
        let data = Data(pin.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Session Management

    /// Unlock session for limited time.
    private func unlockSession() {
        isUnlocked = true
        let expiration = Date().addingTimeInterval(sessionDuration)
        userDefaults.set(expiration, forKey: unlockExpirationKey)
    }

    /// Lock session immediately.
    public func lockSession() {
        isUnlocked = false
        userDefaults.removeObject(forKey: unlockExpirationKey)
    }

    /// Extend current session.
    public func extendSession() {
        guard isUnlocked else { return }
        unlockSession()
    }

    // MARK: - Content Filtering

    /// Check if channel is allowed to be viewed.
    public func isChannelAllowed(_ channel: Channel) -> Bool {
        guard settings.isEnabled else { return true }
        guard !isUnlocked else { return true }

        // Check if channel is explicitly locked
        if settings.lockedChannelIds.contains(channel.id) {
            return false
        }

        // Check age rating
        let effectiveMaxRating = getEffectiveMaxRating()
        if let channelRating = channel.ageRating, channelRating > effectiveMaxRating {
            return false
        }

        return true
    }

    /// Get effective max rating considering time restrictions.
    private func getEffectiveMaxRating() -> AgeRating {
        guard settings.isEnabled else { return .nc17 }

        let now = Date()
        for restriction in settings.timeRestrictions where restriction.isActive(at: now) {
            return min(restriction.maxAgeRating, settings.maxAgeRating)
        }

        return settings.maxAgeRating
    }

    /// Get reason why channel is blocked.
    public func getBlockReason(for channel: Channel) -> String? {
        guard settings.isEnabled, !isUnlocked else { return nil }

        if settings.lockedChannelIds.contains(channel.id) {
            return "This channel is locked by parental controls"
        }

        let effectiveMaxRating = getEffectiveMaxRating()
        if let channelRating = channel.ageRating, channelRating > effectiveMaxRating {
            return "Content rating (\(channelRating.rawValue)) exceeds allowed rating (\(effectiveMaxRating.rawValue))"
        }

        return nil
    }

    // MARK: - Settings Management

    /// Update parental settings.
    public func updateSettings(_ newSettings: ParentalSettings) throws {
        settings = newSettings
        try saveSettings()
    }

    /// Lock specific channel.
    public func lockChannel(_ channelId: UUID) throws {
        settings.lockedChannelIds.insert(channelId)
        try saveSettings()
    }

    /// Unlock specific channel.
    public func unlockChannel(_ channelId: UUID) throws {
        settings.lockedChannelIds.remove(channelId)
        try saveSettings()
    }

    /// Add time restriction.
    public func addTimeRestriction(_ restriction: TimeRestriction) throws {
        settings.timeRestrictions.append(restriction)
        try saveSettings()
    }

    /// Remove time restriction.
    public func removeTimeRestriction(_ restrictionId: UUID) throws {
        settings.timeRestrictions.removeAll { $0.id == restrictionId }
        try saveSettings()
    }

    private func saveSettings() throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: settingsKey)
    }
}

// MARK: - Errors

public enum ParentalControlError: Error, LocalizedError {
    case invalidPIN
    case incorrectPIN
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .invalidPIN:
            return "PIN must be 4 digits"
        case .incorrectPIN:
            return "Incorrect PIN"
        case .notConfigured:
            return "Parental controls not configured"
        }
    }
}

// MARK: - Channel Extension

extension Channel {
    /// Age rating for this channel (if specified in metadata).
    public var ageRating: AgeRating? {
        // Parse from group title or name
        let text = "\(groupTitle) \(name)".lowercased()

        if text.contains("nc-17") || text.contains("nc17") || text.contains("adult") {
            return .nc17
        } else if text.contains(" r ") || text.contains("rated r") {
            return .r
        } else if text.contains("pg-13") || text.contains("pg13") {
            return .pg13
        } else if text.contains("pg") {
            return .pg
        } else if text.contains(" g ") || text.contains("general") {
            return .g
        }

        return .unrated
    }
}
