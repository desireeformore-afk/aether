import Foundation
import Network

/// Network connectivity status.
public enum NetworkStatus: Sendable {
    case connected
    case disconnected
    case unknown
}

/// Service for monitoring network connectivity and handling reconnection.
@MainActor
public final class NetworkMonitorService: ObservableObject {
    @Published public private(set) var status: NetworkStatus = .unknown
    @Published public private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.aether.networkmonitor")
    private var reconnectTask: Task<Void, Never>?

    public var onNetworkRestored: (() -> Void)?
    public var onNetworkLost: (() -> Void)?

    public init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let wasOnline = self.isOnline
                self.isOnline = path.status == .satisfied

                if self.isOnline {
                    self.status = .connected
                    if !wasOnline {
                        // Network restored
                        self.onNetworkRestored?()
                    }
                } else {
                    self.status = .disconnected
                    if wasOnline {
                        // Network lost
                        self.onNetworkLost?()
                    }
                }
            }
        }

        monitor.start(queue: queue)
    }

    private func stopMonitoring() {
        monitor.cancel()
    }

    // MARK: - Reconnection

    /// Attempt to reconnect with exponential backoff.
    public func attemptReconnect(maxAttempts: Int = 5, onSuccess: @escaping () async -> Void) {
        reconnectTask?.cancel()

        reconnectTask = Task {
            var attempt = 0
            var delay: TimeInterval = 1.0

            while attempt < maxAttempts && !Task.isCancelled {
                attempt += 1

                // Wait before attempting
                try? await Task.sleep(for: .seconds(delay))

                guard !Task.isCancelled else { return }

                // Check if network is available
                if isOnline {
                    await onSuccess()
                    return
                }

                // Exponential backoff
                delay = min(delay * 2, 30.0)
            }
        }
    }

    /// Cancel any pending reconnection attempts.
    public func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }
}

/// Service for handling offline operations and queuing.
@MainActor
public final class OfflineQueueService: ObservableObject {
    @Published public private(set) var queuedOperations: [QueuedOperation] = []

    private let networkMonitor: NetworkMonitorService

    public init(networkMonitor: NetworkMonitorService) {
        self.networkMonitor = networkMonitor

        // Process queue when network is restored
        networkMonitor.onNetworkRestored = { [weak self] in
            Task { @MainActor in
                await self?.processQueue()
            }
        }
    }

    // MARK: - Queue Management

    /// Add an operation to the queue.
    public func enqueue(_ operation: QueuedOperation) {
        queuedOperations.append(operation)
    }

    /// Process all queued operations.
    public func processQueue() async {
        guard networkMonitor.isOnline else { return }

        let operations = queuedOperations
        queuedOperations.removeAll()

        for operation in operations {
            do {
                try await operation.execute()
            } catch {
                // Re-queue failed operations
                queuedOperations.append(operation)
            }
        }
    }

    /// Clear all queued operations.
    public func clearQueue() {
        queuedOperations.removeAll()
    }
}

/// A queued operation to be executed when network is available.
public struct QueuedOperation: Identifiable, Sendable {
    public let id: UUID
    public var type: OperationType
    public var timestamp: Date
    public var execute: @Sendable () async throws -> Void

    public init(
        id: UUID = UUID(),
        type: OperationType,
        timestamp: Date = Date(),
        execute: @escaping @Sendable () async throws -> Void
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.execute = execute
    }

    public enum OperationType: String, Sendable {
        case epgUpdate = "EPG Update"
        case playlistRefresh = "Playlist Refresh"
        case recordingUpload = "Recording Upload"
        case other = "Other"
    }
}
