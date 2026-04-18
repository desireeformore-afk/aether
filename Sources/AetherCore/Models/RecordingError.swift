import Foundation

/// Errors related to recording operations.
public enum RecordingError: Error, LocalizedError {
    case recordingNotFound
    case scheduleNotFound
    case diskSpaceFull
    case writeFailed
    case invalidFormat
    case alreadyRecording

    public var errorDescription: String? {
        switch self {
        case .recordingNotFound:
            return "Recording not found"
        case .scheduleNotFound:
            return "Scheduled recording not found"
        case .diskSpaceFull:
            return "Not enough disk space to record"
        case .writeFailed:
            return "Failed to write recording to disk"
        case .invalidFormat:
            return "Invalid recording format"
        case .alreadyRecording:
            return "Already recording this channel"
        }
    }
}
