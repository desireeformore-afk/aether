import Foundation

enum LocalPlaybackProxyError: Error, LocalizedError, Equatable {
    case ffmpegUnavailable
    case startupTimedOut
    case processExited(Int32, String)

    var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable:
            return "ffmpeg is not installed"
        case .startupTimedOut:
            return "local HLS remux did not become ready in time"
        case .processExited(let status, let output):
            if output.isEmpty {
                return "ffmpeg exited with status \(status)"
            }
            return "ffmpeg exited with status \(status): \(output)"
        }
    }
}

actor LocalPlaybackProxy {
    private static let defaultCandidates = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]
    private static let startupTimeoutSeconds: TimeInterval = 8.0
    private static let playlistPollMilliseconds = 150

    #if os(macOS)
    private var process: Process?
    private var logBuffer: LocalPlaybackProxyLogBuffer?
    #endif
    private var directoryURL: URL?
    private var sessionID: UUID?

    static var isFFmpegAvailable: Bool {
        resolvedFFmpegPath() != nil
    }

    static func resolvedFFmpegPath(
        candidates: [String] = defaultCandidates,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        for candidate in candidates where isExecutable(candidate) {
            return candidate
        }

        let pathCandidates = (environmentPath ?? "")
            .split(separator: ":")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg").path }

        return pathCandidates.first(where: isExecutable)
    }

    func startHLS(
        for remoteURL: URL,
        startPosition: Double,
        userAgent: String
    ) async throws -> URL {
        #if os(macOS)
        guard let ffmpegPath = Self.resolvedFFmpegPath() else {
            throw LocalPlaybackProxyError.ffmpegUnavailable
        }

        stopCurrentProcess(removeFiles: true)

        let id = UUID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aether-local-hls-\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let playlistURL = directory.appendingPathComponent("index.m3u8")
        let logBuffer = LocalPlaybackProxyLogBuffer()
        let errorPipe = Pipe()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            logBuffer.append(handle.availableData)
        }

        let outputPipe = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            logBuffer.append(handle.availableData)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = Self.hlsArguments(
            remoteURL: remoteURL,
            startPosition: startPosition,
            playlistURL: playlistURL,
            userAgent: userAgent
        )
        process.standardError = errorPipe
        process.standardOutput = outputPipe

        self.process = process
        self.logBuffer = logBuffer
        self.directoryURL = directory
        self.sessionID = id

        do {
            try process.run()
            try await waitForPlayablePlaylist(
                playlistURL: playlistURL,
                sessionID: id,
                process: process,
                logBuffer: logBuffer
            )
            return playlistURL
        } catch {
            stopCurrentProcess(removeFiles: true)
            throw error
        }
        #else
        throw LocalPlaybackProxyError.ffmpegUnavailable
        #endif
    }

    func stop() {
        stopCurrentProcess(removeFiles: true)
    }

    static func hlsArguments(
        remoteURL: URL,
        startPosition: Double,
        playlistURL: URL,
        userAgent: String
    ) -> [String] {
        let directory = playlistURL.deletingLastPathComponent()
        let segmentPattern = directory.appendingPathComponent("segment_%05d.ts").path
        let start = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(0, startPosition))
        let scheme = remoteURL.scheme?.lowercased()

        var arguments = [
            "-hide_banner",
            "-loglevel", "warning",
            "-nostdin"
        ]

        if scheme == "http" || scheme == "https" {
            arguments += [
                "-user_agent", userAgent,
                "-reconnect", "1",
                "-reconnect_streamed", "1",
                "-reconnect_at_eof", "1",
                "-reconnect_delay_max", "2"
            ]
        }

        arguments += [
            "-ss", start,
            "-i", remoteURL.absoluteString,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-dn",
            "-sn",
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            "-fflags", "+genpts",
            "-max_muxing_queue_size", "2048",
            "-muxdelay", "0",
            "-muxpreload", "0",
            "-f", "hls",
            "-hls_time", "2",
            "-hls_list_size", "0",
            "-start_number", "0",
            "-hls_playlist_type", "event",
            "-hls_flags", "independent_segments+temp_file",
            "-hls_segment_type", "mpegts",
            "-hls_segment_filename", segmentPattern,
            playlistURL.path
        ]
        return arguments
    }

    #if os(macOS)
    private func waitForPlayablePlaylist(
        playlistURL: URL,
        sessionID: UUID,
        process: Process,
        logBuffer: LocalPlaybackProxyLogBuffer
    ) async throws {
        let deadline = Date().addingTimeInterval(Self.startupTimeoutSeconds)
        while Date() < deadline {
            try Task.checkCancellation()
            guard self.sessionID == sessionID else { throw CancellationError() }

            if playlistIsPlayable(at: playlistURL) {
                return
            }

            if !process.isRunning {
                throw LocalPlaybackProxyError.processExited(
                    process.terminationStatus,
                    logBuffer.snapshot()
                )
            }

            try await Task.sleep(for: .milliseconds(Self.playlistPollMilliseconds))
        }

        throw LocalPlaybackProxyError.startupTimedOut
    }
    #endif

    private func playlistIsPlayable(at playlistURL: URL) -> Bool {
        guard let text = try? String(contentsOf: playlistURL, encoding: .utf8) else {
            return false
        }
        return Self.playlistHasPlayableSegments(
            text,
            baseURL: playlistURL.deletingLastPathComponent()
        )
    }

    static func playlistHasPlayableSegments(
        _ text: String,
        baseURL: URL? = nil,
        minimumSegments: Int = 2
    ) -> Bool {
        guard !text.contains("#EXT-X-MAP") else { return false }

        var playableSegments = 0
        var pendingPositiveDuration = false

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF:") {
                let durationText = line
                    .dropFirst("#EXTINF:".count)
                    .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init) ?? ""
                let duration = Double(durationText) ?? 0
                pendingPositiveDuration = duration > 0.05 && duration.isFinite
                continue
            }

            guard !line.hasPrefix("#"), pendingPositiveDuration else { continue }
            pendingPositiveDuration = false

            if let baseURL {
                let segmentURL = baseURL.appendingPathComponent(line)
                let attributes = try? FileManager.default.attributesOfItem(atPath: segmentURL.path)
                let fileSize = attributes?[.size] as? NSNumber
                guard (fileSize?.intValue ?? 0) > 0 else { continue }
            }

            playableSegments += 1
            if playableSegments >= minimumSegments {
                return true
            }
        }

        return false
    }

    private func stopCurrentProcess(removeFiles: Bool) {
        #if os(macOS)
        process?.terminate()
        process = nil
        logBuffer = nil
        #endif

        let oldDirectory = directoryURL
        directoryURL = nil
        sessionID = nil

        if removeFiles, let oldDirectory {
            try? FileManager.default.removeItem(at: oldDirectory)
        }
    }
}

private final class LocalPlaybackProxyLogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        lock.lock()
        defer { lock.unlock() }
        text += chunk
        if text.count > 2_000 {
            text = String(text.suffix(2_000))
        }
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}
