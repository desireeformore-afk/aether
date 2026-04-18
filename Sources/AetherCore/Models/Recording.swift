import Foundation

/// A recorded stream session.
public struct Recording: Identifiable, Codable, Sendable {
    public let id: UUID
    public var channelName: String
    public var channelId: UUID
    public var startTime: Date
    public var endTime: Date?
    public var fileURL: URL
    public var fileSize: Int64
    public var duration: TimeInterval
    public var isComplete: Bool
    public var programTitle: String?
    public var programDescription: String?

    public init(
        id: UUID = UUID(),
        channelName: String,
        channelId: UUID,
        startTime: Date,
        endTime: Date? = nil,
        fileURL: URL,
        fileSize: Int64 = 0,
        duration: TimeInterval = 0,
        isComplete: Bool = false,
        programTitle: String? = nil,
        programDescription: String? = nil
    ) {
        self.id = id
        self.channelName = channelName
        self.channelId = channelId
        self.startTime = startTime
        self.endTime = endTime
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.duration = duration
        self.isComplete = isComplete
        self.programTitle = programTitle
        self.programDescription = programDescription
    }

    /// Human-readable file size.
    public var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// Human-readable duration.
    public var durationFormatted: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

/// A scheduled recording.
public struct RecordingSchedule: Identifiable, Codable, Sendable {
    public let id: UUID
    public var channelId: UUID
    public var channelName: String
    public var startTime: Date
    public var duration: TimeInterval
    public var programTitle: String?
    public var isRecurring: Bool
    public var daysOfWeek: Set<Int>
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        channelId: UUID,
        channelName: String,
        startTime: Date,
        duration: TimeInterval,
        programTitle: String? = nil,
        isRecurring: Bool = false,
        daysOfWeek: Set<Int> = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.channelId = channelId
        self.channelName = channelName
        self.startTime = startTime
        self.duration = duration
        self.programTitle = programTitle
        self.isRecurring = isRecurring
        self.daysOfWeek = daysOfWeek
        self.isEnabled = isEnabled
    }
}

/// Recording settings.
public struct RecordingSettings: Codable, Sendable {
    public var recordingsDirectory: URL
    public var maxRecordingSize: Int64
    public var autoDeleteAfterDays: Int
    public var recordingQuality: RecordingQuality

    public init(
        recordingsDirectory: URL,
        maxRecordingSize: Int64 = 10_000_000_000, // 10 GB
        autoDeleteAfterDays: Int = 30,
        recordingQuality: RecordingQuality = .high
    ) {
        self.recordingsDirectory = recordingsDirectory
        self.maxRecordingSize = maxRecordingSize
        self.autoDeleteAfterDays = autoDeleteAfterDays
        self.recordingQuality = recordingQuality
    }
}

/// Recording quality preset.
public enum RecordingQuality: String, Codable, Sendable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case source = "source"

    public var displayName: String {
        switch self {
        case .low: return "Low (480p)"
        case .medium: return "Medium (720p)"
        case .high: return "High (1080p)"
        case .source: return "Source (Original)"
        }
    }

    public var bitrate: Int {
        switch self {
        case .low: return 1_500_000
        case .medium: return 3_000_000
        case .high: return 6_000_000
        case .source: return 0 // No transcoding
        }
    }
}
