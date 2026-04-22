import Foundation
@preconcurrency import AVFoundation

/// Service for recording live streams to disk.
///
/// Handles stream recording, file management, and scheduled recordings.
@MainActor
@Observable
public final class RecordingService {
    public private(set) var activeRecordings: [UUID: Recording] = [:]
    public private(set) var completedRecordings: [Recording] = []
    public private(set) var scheduledRecordings: [RecordingSchedule] = []
    public var settings: RecordingSettings

    private var assetWriters: [UUID: AVAssetWriter] = [:]
    private var writerInputs: [UUID: (video: AVAssetWriterInput, audio: AVAssetWriterInput)] = [:]
    private let fileManager = FileManager.default
    private let userDefaults: UserDefaults
    private var scheduleCheckerTask: Task<Void, Never>?

    private let recordingsKey = "aether.recordings.completed"
    private let schedulesKey = "aether.recordings.schedules"
    private let settingsKey = "aether.recordings.settings"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load settings
        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(RecordingSettings.self, from: data) {
            self.settings = decoded
        } else {
            // Default recordings directory
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
            let recordingsURL = documentsURL.appendingPathComponent("Aether/Recordings")
            self.settings = RecordingSettings(recordingsDirectory: recordingsURL)
        }

        // Load completed recordings
        if let data = userDefaults.data(forKey: recordingsKey),
           let decoded = try? JSONDecoder().decode([Recording].self, from: data) {
            self.completedRecordings = decoded
        }

        // Load schedules
        if let data = userDefaults.data(forKey: schedulesKey),
           let decoded = try? JSONDecoder().decode([RecordingSchedule].self, from: data) {
            self.scheduledRecordings = decoded
        }

        // Create recordings directory
        try? fileManager.createDirectory(at: settings.recordingsDirectory, withIntermediateDirectories: true)

        // Start schedule checker — stored so it can be cancelled on deinit
        scheduleCheckerTask = Task {
            await checkScheduledRecordings()
        }
    }

    deinit {
        scheduleCheckerTask?.cancel()
    }

    // MARK: - Recording Control

    /// Start recording a channel.
    public func startRecording(
        channel: Channel,
        programTitle: String? = nil,
        programDescription: String? = nil
    ) throws -> UUID {
        let recordingId = UUID()
        let fileName = "\(channel.name)_\(Date().timeIntervalSince1970).mp4"
        let fileURL = settings.recordingsDirectory.appendingPathComponent(fileName)

        let recording = Recording(
            id: recordingId,
            channelName: channel.name,
            channelId: channel.id,
            startTime: Date(),
            fileURL: fileURL,
            programTitle: programTitle,
            programDescription: programDescription
        )

        activeRecordings[recordingId] = recording

        // Note: Actual AVAssetWriter setup would require access to the AVPlayer's output
        // This is a simplified implementation
        return recordingId
    }

    /// Stop an active recording.
    public func stopRecording(_ recordingId: UUID) async throws {
        guard var recording = activeRecordings[recordingId] else {
            throw RecordingError.recordingNotFound
        }

        // Finalize the recording
        if let writer = assetWriters[recordingId] {
            await writer.finishWriting()
            assetWriters.removeValue(forKey: recordingId)
            writerInputs.removeValue(forKey: recordingId)
        }

        let endTime = Date()
        recording.endTime = endTime
        recording.isComplete = true
        recording.duration = endTime.timeIntervalSince(recording.startTime)

        // Get file size
        if let attrs = try? fileManager.attributesOfItem(atPath: recording.fileURL.path),
           let size = attrs[.size] as? Int64 {
            recording.fileSize = size
        }

        activeRecordings.removeValue(forKey: recordingId)
        completedRecordings.append(recording)

        try saveRecordings()
    }

    /// Delete a recording.
    public func deleteRecording(_ recordingId: UUID) throws {
        guard let index = completedRecordings.firstIndex(where: { $0.id == recordingId }) else {
            throw RecordingError.recordingNotFound
        }

        let recording = completedRecordings[index]

        // Delete file
        try? fileManager.removeItem(at: recording.fileURL)

        completedRecordings.remove(at: index)
        try saveRecordings()
    }

    /// Export recording to a different location.
    public func exportRecording(_ recordingId: UUID, to destinationURL: URL) throws {
        guard let recording = completedRecordings.first(where: { $0.id == recordingId }) else {
            throw RecordingError.recordingNotFound
        }

        try fileManager.copyItem(at: recording.fileURL, to: destinationURL)
    }

    // MARK: - Scheduled Recordings

    /// Schedule a recording.
    public func scheduleRecording(_ schedule: RecordingSchedule) throws {
        scheduledRecordings.append(schedule)
        try saveSchedules()
    }

    /// Cancel a scheduled recording.
    public func cancelSchedule(_ scheduleId: UUID) throws {
        scheduledRecordings.removeAll { $0.id == scheduleId }
        try saveSchedules()
    }

    /// Update a scheduled recording.
    public func updateSchedule(_ schedule: RecordingSchedule) throws {
        guard let index = scheduledRecordings.firstIndex(where: { $0.id == schedule.id }) else {
            throw RecordingError.scheduleNotFound
        }
        scheduledRecordings[index] = schedule
        try saveSchedules()
    }

    /// Check for scheduled recordings that should start. Loops until task is cancelled.
    private func checkScheduledRecordings() async {
        while !Task.isCancelled {
            let now = Date()
            for schedule in scheduledRecordings where schedule.isEnabled {
                if abs(schedule.startTime.timeIntervalSince(now)) < 60 {
                    // Placeholder — actual implementation requires channel access
                }
            }
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                break // cancelled
            }
        }
    }

    // MARK: - Auto-Delete

    /// Delete recordings older than the configured retention period.
    public func autoDeleteOldRecordings() throws {
        let cutoffDate = Date().addingTimeInterval(-Double(settings.autoDeleteAfterDays) * 86400)

        let toDelete = completedRecordings.filter { $0.startTime < cutoffDate }

        for recording in toDelete {
            try? deleteRecording(recording.id)
        }
    }

    // MARK: - Storage Management

    /// Get total size of all recordings.
    public func getTotalRecordingsSize() -> Int64 {
        completedRecordings.reduce(0) { $0 + $1.fileSize }
    }

    /// Check if there's enough space for a new recording.
    public func hasEnoughSpace(estimatedSize: Int64) -> Bool {
        let currentSize = getTotalRecordingsSize()
        return (currentSize + estimatedSize) < settings.maxRecordingSize
    }

    // MARK: - Settings

    /// Update recording settings.
    public func updateSettings(_ newSettings: RecordingSettings) throws {
        settings = newSettings
        try saveSettings()
    }

    // MARK: - Persistence

    private func saveRecordings() throws {
        let data = try JSONEncoder().encode(completedRecordings)
        userDefaults.set(data, forKey: recordingsKey)
    }

    private func saveSchedules() throws {
        let data = try JSONEncoder().encode(scheduledRecordings)
        userDefaults.set(data, forKey: schedulesKey)
    }

    private func saveSettings() throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: settingsKey)
    }
}
