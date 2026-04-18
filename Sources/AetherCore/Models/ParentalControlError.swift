import Foundation

/// Errors related to parental control operations.
public enum ParentalControlError: Error, LocalizedError {
    case invalidPIN
    case incorrectPIN
    case notEnabled
    case saveFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPIN:
            return "PIN must be exactly 4 digits"
        case .incorrectPIN:
            return "Incorrect PIN"
        case .notEnabled:
            return "Parental controls are not enabled"
        case .saveFailed:
            return "Failed to save parental control settings"
        }
    }
}
