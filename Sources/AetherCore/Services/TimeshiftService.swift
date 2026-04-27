import Foundation
import Observation
@preconcurrency import AVFoundation

/// Service for timeshift (pause live TV) functionality.
///
/// Buffers live stream to disk to enable pause/rewind of live content.
@MainActor
@Observable
public final class TimeshiftService {
    public private(set) var isBuffering: Bool = false
    public private(set) var bufferDuration: TimeInterval = 0
    public private(set) var bufferSize: Int64 = 0
    public var isPaused: Bool = false

    private var bufferURL: URL?
    private var assetWriter: AVAssetWriter?
    private var startTime: Date?
    private let maxBufferDuration: TimeInterval = 3600 // 1 hour
    private let maxBufferSize: Int64 = 2_000_000_000 // 2 GB

    private let fileManager = FileManager.default

    public init() {
        setupBufferDirectory()
    }

    // MARK: - Buffer Management

    /// Start buffering the current stream.
    public func startBuffering(for channelId: UUID) throws {
        guard !isBuffering else { return }

        let tempDir = fileManager.temporaryDirectory
        let bufferFile = tempDir.appendingPathComponent("timeshift_\(channelId.uuidString).mp4")

        // Clean up old buffer if exists
        try? fileManager.removeItem(at: bufferFile)

        bufferURL = bufferFile
        startTime = Date()
        isBuffering = true
        bufferDuration = 0
        bufferSize = 0

        // Note: Actual AVAssetWriter setup would require access to the AVPlayer's output
        // This is a simplified implementation
    }

    /// Stop buffering and clean up.
    public func stopBuffering() {
        isBuffering = false
        isPaused = false

        if let url = bufferURL {
            try? fileManager.removeItem(at: url)
        }

        bufferURL = nil
        assetWriter = nil
        startTime = nil
        bufferDuration = 0
        bufferSize = 0
    }

    /// Pause live TV (continue buffering in background).
    public func pause() {
        guard isBuffering else { return }
        isPaused = true
    }

    /// Resume live TV.
    public func resume() {
        isPaused = false
    }

    /// Seek to a specific time in the buffer.
    public func seek(to time: TimeInterval) throws {
        guard isBuffering, let start = startTime else {
            throw TimeshiftError.notBuffering
        }

        let elapsed = Date().timeIntervalSince(start)
        guard time >= 0 && time <= elapsed else {
            throw TimeshiftError.invalidSeekTime
        }

        // Seek implementation would interact with AVPlayer
    }

    /// Jump back by a specific duration.
    public func jumpBack(seconds: TimeInterval = 10) throws {
        guard isBuffering, let start = startTime else {
            throw TimeshiftError.notBuffering
        }

        let currentTime = Date().timeIntervalSince(start)
        let newTime = max(0, currentTime - seconds)
        try seek(to: newTime)
    }

    /// Jump forward by a specific duration.
    public func jumpForward(seconds: TimeInterval = 10) throws {
        guard isBuffering, let start = startTime else {
            throw TimeshiftError.notBuffering
        }

        let currentTime = Date().timeIntervalSince(start)
        let elapsed = Date().timeIntervalSince(start)
        let newTime = min(elapsed, currentTime + seconds)
        try seek(to: newTime)
    }

    /// Update buffer statistics.
    public func updateBufferStats() {
        guard isBuffering, let start = startTime, let url = bufferURL else { return }

        bufferDuration = Date().timeIntervalSince(start)

        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            bufferSize = size
        }

        // Check if buffer limits exceeded
        if bufferDuration > maxBufferDuration || bufferSize > maxBufferSize {
            // Trim old buffer data (implementation would require more complex logic)
        }
    }

    /// Get human-readable buffer duration.
    public var bufferDurationFormatted: String {
        let minutes = Int(bufferDuration) / 60
        let seconds = Int(bufferDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Get human-readable buffer size.
    public var bufferSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bufferSize)
    }

    // MARK: - Private Helpers

    private func setupBufferDirectory() {
        let tempDir = fileManager.temporaryDirectory
        let bufferDir = tempDir.appendingPathComponent("AetherTimeshift")
        try? fileManager.createDirectory(at: bufferDir, withIntermediateDirectories: true)

        // Clean up old timeshift files on startup
        if let files = try? fileManager.contentsOfDirectory(at: bufferDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("timeshift_") {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}

/// Errors related to timeshift operations.
public enum TimeshiftError: Error, LocalizedError {
    case notBuffering
    case invalidSeekTime
    case bufferFull

    public var errorDescription: String? {
        switch self {
        case .notBuffering:
            return "Timeshift is not active"
        case .invalidSeekTime:
            return "Invalid seek time"
        case .bufferFull:
            return "Timeshift buffer is full"
        }
    }
}
