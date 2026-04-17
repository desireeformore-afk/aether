import Foundation

// MARK: - Channel Health Status

public enum ChannelHealth: Sendable {
    case ok(latencyMs: Int)
    case slow(latencyMs: Int)   // > 2000ms
    case dead                   // non-2xx or unreachable
    case unknown                // not yet checked

    public var icon: String {
        switch self {
        case .ok:      return "checkmark.circle.fill"
        case .slow:    return "exclamationmark.circle.fill"
        case .dead:    return "xmark.circle.fill"
        case .unknown: return "circle"
        }
    }

    public var label: String {
        switch self {
        case .ok(let ms):   return "OK (\(ms) ms)"
        case .slow(let ms): return "Slow (\(ms) ms)"
        case .dead:         return "Unreachable"
        case .unknown:      return "—"
        }
    }

    public var isHealthy: Bool {
        if case .ok = self { return true }
        return false
    }
}

// MARK: - Channel Check Result

public struct ChannelCheckResult: Sendable, Identifiable {
    public let id: UUID
    public let channelName: String
    public let streamURL: URL
    public let health: ChannelHealth

    public init(id: UUID = UUID(), channelName: String, streamURL: URL, health: ChannelHealth) {
        self.id = id
        self.channelName = channelName
        self.streamURL = streamURL
        self.health = health
    }
}

// MARK: - Playlist Validator

/// Concurrently pings stream URLs with HEAD requests to assess playlist health.
public actor PlaylistValidator {

    private let timeoutSeconds: Double
    private let slowThresholdMs: Int
    private let maxConcurrency: Int

    public init(timeoutSeconds: Double = 8.0, slowThresholdMs: Int = 2000, maxConcurrency: Int = 20) {
        self.timeoutSeconds = timeoutSeconds
        self.slowThresholdMs = slowThresholdMs
        self.maxConcurrency = maxConcurrency
    }

    // MARK: - Public API

    /// Validate all channels in the playlist concurrently.
    /// - Parameter channels: Array of (name, url) tuples to check.
    /// - Parameter onProgress: Optional progress callback (checked count, total count).
    /// - Returns: Array of `ChannelCheckResult` in the same order as input.
    public func validate(
        channels: [(name: String, url: URL)],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [ChannelCheckResult] {
        let total = channels.count
        guard total > 0 else { return [] }

        // Use a semaphore-like approach via task groups with concurrency cap
        var results: [ChannelCheckResult] = []
        var checkedCount = 0

        let session = URLSession(configuration: makeSessionConfig())

        await withTaskGroup(of: ChannelCheckResult.self) { group in
            var pending = channels.makeIterator()
            var inFlight = 0

            // Seed initial tasks up to maxConcurrency
            while inFlight < maxConcurrency, let next = pending.next() {
                let name = next.name
                let url = next.url
                group.addTask {
                    await self.checkChannel(name: name, url: url, session: session)
                }
                inFlight += 1
            }

            // Harvest results and schedule more as slots open
            for await result in group {
                results.append(result)
                checkedCount += 1
                onProgress?(checkedCount, total)

                if let next = pending.next() {
                    let name = next.name
                    let url = next.url
                    group.addTask {
                        await self.checkChannel(name: name, url: url, session: session)
                    }
                }
            }
        }

        // Re-sort to original order
        let ordered = channels.map { ch in
            results.first { $0.channelName == ch.name && $0.streamURL == ch.url }
                ?? ChannelCheckResult(channelName: ch.name, streamURL: ch.url, health: .unknown)
        }

        return ordered
    }

    // MARK: - Single channel check

    private func checkChannel(name: String, url: URL, session: URLSession) async -> ChannelCheckResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutSeconds)
        request.httpMethod = "HEAD"

        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let isOK = (200...299).contains(statusCode) || statusCode == 401 // 401 = auth needed but stream exists

            if isOK {
                let health: ChannelHealth = elapsedMs > slowThresholdMs ? .slow(latencyMs: elapsedMs) : .ok(latencyMs: elapsedMs)
                return ChannelCheckResult(channelName: name, streamURL: url, health: health)
            } else {
                return ChannelCheckResult(channelName: name, streamURL: url, health: .dead)
            }
        } catch {
            return ChannelCheckResult(channelName: name, streamURL: url, health: .dead)
        }
    }

    // MARK: - Session config

    private func makeSessionConfig() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds + 2
        config.waitsForConnectivity = false
        return config
    }
}

// MARK: - Summary

public struct PlaylistHealthSummary: Sendable {
    public let total: Int
    public let ok: Int
    public let slow: Int
    public let dead: Int
    public let unknown: Int

    public init(results: [ChannelCheckResult]) {
        total = results.count
        ok    = results.filter { guard case .ok   = $0.health else { return false }; return true }.count
        slow  = results.filter { guard case .slow = $0.health else { return false }; return true }.count
        dead  = results.filter { guard case .dead = $0.health else { return false }; return true }.count
        unknown = results.filter { guard case .unknown = $0.health else { return false }; return true }.count
    }

    public var healthPercent: Int {
        guard total > 0 else { return 0 }
        return Int(Double(ok + slow) * 100 / Double(total))
    }
}
