import Foundation
import Network

// MARK: - Mini HTTP Server

/// Serves files from a local directory over HTTP on localhost.
/// Required because AVPlayer's HLS stack doesn't work with file:// URLs
/// (causes HLSPersistentStore -16913 error without a bundle identifier).
private final class MiniHTTPServer: @unchecked Sendable {
    private let rootDir: URL
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    init(rootDir: URL) {
        self.rootDir = rootDir
    }

    func start() throws -> UInt16 {
        let params = NWParameters.tcp
        // Allow port reuse to avoid "address already in use" on rapid restarts
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        let sem = DispatchSemaphore(value: 0)

        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.port = listener.port?.rawValue ?? 0
                print("[MiniHTTP] Listening on port \(self?.port ?? 0)")
                sem.signal()
            }
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        listener.start(queue: DispatchQueue.global(qos: .userInitiated))

        if sem.wait(timeout: .now() + 3) == .timedOut {
            throw NSError(domain: "MiniHTTPServer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP server start timeout"])
        }
        return port
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data else { conn.cancel(); return }

            let request = String(data: data, encoding: .utf8) ?? ""
            // Parse: "GET /stream.m3u8 HTTP/1.1\r\n..."
            let parts = request.split(separator: " ")
            guard parts.count >= 2 else { conn.cancel(); return }

            let rawPath = String(parts[1])
            let cleanPath = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
            let fileURL = self.rootDir.appendingPathComponent(cleanPath)

            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let fileData = try? Data(contentsOf: fileURL) else {
                let resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
                return
            }

            let mime: String
            if cleanPath.hasSuffix(".m3u8") {
                mime = "application/vnd.apple.mpegurl"
            } else if cleanPath.hasSuffix(".ts") {
                mime = "video/mp2t"
            } else {
                mime = "application/octet-stream"
            }

            // Allow CORS and disable caching for live HLS
            let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: \(fileData.count)\r\nCache-Control: no-cache, no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            var response = Data(header.utf8)
            response.append(fileData)

            conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

// MARK: - LocalHLSProxy

/// Remuxes raw MPEG-TS (or MKV) streams to HLS segments via FFmpeg
/// and serves them over a local HTTP server for AVPlayer.
///
/// AVPlayer cannot play continuous MPEG-TS over HTTP (-12939 byte-range error)
/// or MKV containers (-12847). This proxy:
/// 1. Runs FFmpeg to remux the stream into HLS segments (M3U8 + .ts files)
/// 2. Serves those files via a local HTTP server on 127.0.0.1
/// 3. Returns an HTTP URL that AVPlayer can play natively
public final class LocalHLSProxy: @unchecked Sendable {

    private var ffmpegProcess: Process?
    private var httpServer: MiniHTTPServer?
    private let outputDir: URL
    private let id = UUID().uuidString.prefix(8)

    /// Set by stop() to signal the startup loop to abort without triggering a retry.
    private var isCancelled = false
    /// Set after process.run() succeeds — guards stop() so we know whether to waitUntilExit.
    private var ffmpegStarted = false

    public init() {
        outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aether-hls-\(id)")
    }

    // MARK: - FFmpeg Detection

    /// Whether FFmpeg is available on this system.
    public static var isAvailable: Bool {
        ffmpegURL != nil
    }

    private static var ffmpegURL: URL? {
        findBinary("ffmpeg")
    }

    private static var ffprobeURL: URL? {
        findBinary("ffprobe")
    }

    private static func findBinary(_ name: String) -> URL? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Probe the video codec of a remote URL using ffprobe.
    /// Returns "hevc", "h264", etc. Falls back to "h264" if probe fails.
    private static func probeVideoCodec(url: URL) -> String {
        guard let ffprobe = ffprobeURL else { return "h264" }

        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "quiet",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_name",
            "-of", "csv=p=0",
            "-probesize", "2000000",
            "-analyzeduration", "2000000",
            "-headers", "User-Agent: \(userAgent)\r\n",
            "-rw_timeout", "5000000",
            url.absoluteString
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let codec = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? "h264"
            print("[HLSProxy] Detected video codec: \(codec)")
            return codec.isEmpty ? "h264" : codec
        } catch {
            print("[HLSProxy] ffprobe failed, assuming h264")
            return "h264"
        }
    }

    // Spoofed User-Agent — many IPTV servers block ffmpeg's default UA with 400/403
    private static let userAgent = "VLC/3.0.20 LibVLC/3.0.20"

    // MARK: - Public API

    /// HTTP URL of the HLS playlist (set after `start()` completes).
    public private(set) var playlistURL: URL = URL(string: "about:blank")!

    /// The current base URL of the local HTTP server (host+port), or nil if not running.
    /// Use this to build segment URLs after a proxy restart.
    public var currentStreamURL: URL? {
        guard let server = httpServer, server.port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(server.port)/stream.m3u8")
    }

    /// Whether FFmpeg is currently running.
    public var isRunning: Bool {
        ffmpegProcess?.isRunning == true
    }

    /// Start remuxing `sourceURL` to local HLS served via HTTP.
    /// Returns when the first HLS segment is ready (or throws on timeout/error).
    public func start(from sourceURL: URL) async throws {
        stop()
        // Reset flags AFTER stop() so any in-progress polling loop is aborted first,
        // then we start fresh for this invocation.
        isCancelled = false
        ffmpegStarted = false

        guard let ffmpeg = Self.ffmpegURL else {
            throw ProxyError.ffmpegNotFound
        }

        // Create fresh output directory — must exist before FFmpeg starts writing segments
        try? FileManager.default.removeItem(at: outputDir)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: outputDir.path) else {
            throw ProxyError.ffmpegFailed("Failed to create temp directory: \(outputDir.path)")
        }
        print("[HLSProxy] Temp dir: \(outputDir.path)")

        // 1. Start local HTTP server
        let server = MiniHTTPServer(rootDir: outputDir)
        let port = try server.start()
        self.httpServer = server
        self.playlistURL = URL(string: "http://127.0.0.1:\(port)/stream.m3u8")!

        // 2. Start FFmpeg
        let m3u8Path = outputDir.appendingPathComponent("stream.m3u8").path
        let segPattern = outputDir.appendingPathComponent("seg_%05d.ts").path

        // Detect VOD vs Live based on URL extension
        let ext = sourceURL.pathExtension.lowercased()
        let isVOD = ["mkv", "mp4", "avi", "mov", "wmv"].contains(ext)

        // For VOD, probe the video codec to select correct bitstream filter
        let videoCodec: String
        if isVOD {
            // probeVideoCodec() calls waitUntilExit() — run it off the MainActor
            // so the UI stays responsive while ffprobe probes the stream.
            videoCodec = await Task.detached(priority: .userInitiated) {
                Self.probeVideoCodec(url: sourceURL)
            }.value
        } else {
            videoCodec = "unknown"
        }

        let process = Process()
        process.executableURL = ffmpeg

        var args: [String] = [
            "-y",
            "-loglevel", "warning",
            "-fflags", "+genpts+discardcorrupt+nobuffer",
            // Spoof User-Agent — IPTV servers often return 400 for ffmpeg's default UA
            "-user_agent", Self.userAgent,
            "-headers", "Accept: */*\r\nAccept-Language: en-US,en;q=0.9\r\n",
            // TCP/HTTP connection options: auto-reconnect on drop
            "-reconnect", "1",
            "-reconnect_at_eof", "1",
            "-reconnect_streamed", "1",
            "-reconnect_delay_max", "5",
            "-max_delay", "500000",
        ]

        if isVOD {
            // VOD: small probesize = faster first segment.
            // 1MB is enough for most MKV/MP4 headers; original 5MB caused ~10s stall
            // before FFmpeg could write the first HLS segment.
            args += [
                "-reconnect_on_http_error", "4xx,5xx",
                "-timeout", "30000000",
                "-rw_timeout", "30000000",
                "-probesize", "1000000", "-analyzeduration", "1000000",
            ]
        } else {
            // Live: minimize startup latency
            args += ["-timeout", "10000000", "-probesize", "1000000", "-analyzeduration", "1000000"]
        }

        args += ["-i", sourceURL.absoluteString]

        if isVOD {
            // VOD (MKV/MP4): pick correct bitstream filter based on detected codec
            let bsfFilter: String
            let isHEVC: Bool
            switch videoCodec {
            case "hevc", "h265":
                bsfFilter = "hevc_mp4toannexb"
                isHEVC = true
            case "h264", "avc":
                bsfFilter = "h264_mp4toannexb"
                isHEVC = false
            default:
                // For unknown codecs, try without BSF (FFmpeg may auto-detect)
                bsfFilter = ""
                isHEVC = false
            }

            args += [
                "-map", "0:v:0",
                "-map", "0:a:0?",
                "-sn", "-dn",
                "-ignore_unknown",
                "-c:v", "copy",
                "-max_muxing_queue_size", "4096",
                "-c:a", "copy",
            ]
            if isHEVC {
                args += ["-tag:v", "hvc1"]
            }
            if !bsfFilter.isEmpty {
                args += ["-bsf:v", bsfFilter]
            }
            args += [
                "-f", "hls",
                "-hls_time", "3",           // 3s segments = first segment 2x faster to produce
                "-hls_list_size", "0",
                "-hls_playlist_type", "event", // event: AVPlayer starts immediately, doesn't wait for EXT-X-ENDLIST
                "-hls_flags", "independent_segments",
            ]
            print("[HLSProxy] Mode: VOD (\(ext)), codec: \(videoCodec), bsf: \(bsfFilter.isEmpty ? "auto" : bsfFilter)")
        } else {
            // Live TS: let FFmpeg pick streams automatically — explicit mapping fails
            // when the stream hasn't fully buffered headers at probe time.
            args += [
                "-sn", "-dn",
                "-c:v", "copy",
                "-max_muxing_queue_size", "4096",
                "-c:a", "aac",
                "-b:a", "192k",
                "-ac", "2",
                "-f", "hls",
                "-hls_time", "4",
                "-hls_list_size", "5",
                "-hls_flags", "delete_segments+append_list",
            ]
            print("[HLSProxy] Mode: Live (TS)")
        }

        args += ["-hls_segment_filename", segPattern, m3u8Path]
        process.arguments = args
        print("[HLSProxy] FFmpeg cmd: ffmpeg \(args.joined(separator: " "))")
        process.standardOutput = FileHandle.nullDevice

        // Capture stderr for diagnostics
        let errPipe = Pipe()
        process.standardError = errPipe

        print("[HLSProxy] Starting FFmpeg: \(sourceURL.lastPathComponent)")
        print("[HLSProxy] Serving at: \(playlistURL.absoluteString)")

        // Guard: verify outputDir still exists — a concurrent stop() call (e.g. user switches
        // channel while the HTTP server was starting) can remove it after the initial check above.
        guard FileManager.default.fileExists(atPath: outputDir.path) else {
            throw ProxyError.ffmpegFailed("Temp directory removed before FFmpeg could start: \(outputDir.path)")
        }

        // FIX 2: If stop() was called while we were setting up, abort cleanly without leaving
        // a dangling process or triggering a retry loop in the caller.
        guard !isCancelled else {
            throw ProxyError.ffmpegFailed("Proxy cancelled before FFmpeg start")
        }

        try process.run()
        ffmpegStarted = true
        self.ffmpegProcess = process

        // 3. Wait for first segment — 45s max (300*150ms).
        // VOD: with probesize=1MB + hls_time=3s, first segment typically appears in 3-8s.
        let maxWaitIterations = 300
        var stderrLines: [String] = []
        for i in 0..<maxWaitIterations {
            try await Task.sleep(nanoseconds: 150_000_000) // 150ms

            // FIX 2: Abort polling if stop() was called while we were waiting.
            if isCancelled {
                throw ProxyError.ffmpegFailed("Proxy cancelled during startup")
            }

            // Check if process died unexpectedly (still running is normal for VOD during mux)
            if !process.isRunning {
                // For VOD, FFmpeg may finish quickly and exit 0 — that's OK if playlist is ready
                let errData = errPipe.fileHandleForReading.availableData
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                stderrLines = errStr.components(separatedBy: "\n").filter { !$0.isEmpty }
                let trimmed = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
                if FileManager.default.fileExists(atPath: m3u8Path),
                   let content = try? String(contentsOf: URL(fileURLWithPath: m3u8Path), encoding: .utf8),
                   content.contains(".ts") {
                    print("[HLSProxy] FFmpeg finished, playlist ready after \(Double(i + 1) * 0.15)s")
                    return
                }
                print("[HLSProxy] FFmpeg stderr tail: \(stderrLines.suffix(5).joined(separator: " | "))")
                print("[HLSProxy] FFmpeg exited early: \(trimmed.isEmpty ? "(no output)" : String(trimmed.prefix(500)))")
                throw ProxyError.ffmpegFailed(trimmed.isEmpty ? "FFmpeg exited with no output" : trimmed)
            }

            // Collect available stderr lines for diagnostics
            let available = errPipe.fileHandleForReading.availableData
            if let chunk = String(data: available, encoding: .utf8), !chunk.isEmpty {
                stderrLines.append(contentsOf: chunk.components(separatedBy: "\n").filter { !$0.isEmpty })
            }

            // Check if the first segment file exists and playlist references it
            let seg0Path = outputDir.appendingPathComponent("seg_00000.ts").path
            if FileManager.default.fileExists(atPath: seg0Path),
               FileManager.default.fileExists(atPath: m3u8Path),
               let content = try? String(contentsOf: URL(fileURLWithPath: m3u8Path), encoding: .utf8),
               content.contains(".ts") {
                print("[HLSProxy] Ready (seg_00000.ts present) after \(Double(i + 1) * 0.15)s")
                return
            }
        }

        print("[HLSProxy] FFmpeg stderr tail: \(stderrLines.suffix(5).joined(separator: " | "))")
        stop()
        throw ProxyError.timeout
    }

    /// Stop the FFmpeg process, HTTP server, and clean up temp files.
    public func stop() {
        // Signal the startup polling loop to abort before we tear anything down.
        isCancelled = true

        if let process = ffmpegProcess {
            if process.isRunning {
                process.terminate()
                // Wait for the process to fully exit before removing the temp directory —
                // removing it while FFmpeg is still writing causes spurious file-not-found
                // errors in FFmpeg's output, and on the next start() we get a clean dir.
                process.waitUntilExit()
            }
            print("[HLSProxy] Stopped FFmpeg (started: \(ffmpegStarted))")
        }
        ffmpegProcess = nil

        httpServer?.stop()
        httpServer = nil

        try? FileManager.default.removeItem(at: outputDir)
    }

    deinit {
        stop()
    }

    // MARK: - Errors

    public enum ProxyError: LocalizedError {
        case ffmpegNotFound
        case ffmpegFailed(String)
        case timeout

        public var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "FFmpeg not installed. Run: brew install ffmpeg"
            case .ffmpegFailed(let msg):
                return "FFmpeg error: \(msg.prefix(200))"
            case .timeout:
                return "Stream timed out — server did not send data within 30s. The stream may be offline or require a VPN."
            }
        }
    }
}
