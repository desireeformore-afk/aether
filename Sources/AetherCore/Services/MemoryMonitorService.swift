import Foundation
import Combine
import Darwin

extension Notification.Name {
    public static let memoryPressureCritical = Notification.Name("memoryPressureCritical")
}

/// Service for monitoring memory pressure and managing memory usage
@MainActor
public final class MemoryMonitorService: ObservableObject {
    @Published public private(set) var memoryPressure: MemoryPressureLevel = .normal
    @Published public private(set) var currentMemoryUsage: UInt64 = 0
    @Published public private(set) var memoryWarningCount: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private let memoryWarningThreshold: Double = 0.8 // 80% of available memory
    private var memoryCheckTimer: Timer?
    private let originalCache: URLCache

    public enum MemoryPressureLevel: String, Codable {
        case normal
        case warning
        case critical

        public var description: String {
            switch self {
            case .normal: return "Normal"
            case .warning: return "Warning"
            case .critical: return "Critical"
            }
        }
    }

    public struct MemoryEvent: Codable {
        public let timestamp: Date
        public let level: MemoryPressureLevel
        public let memoryUsage: UInt64
        public let action: String

        public init(timestamp: Date, level: MemoryPressureLevel, memoryUsage: UInt64, action: String) {
            self.timestamp = timestamp
            self.level = level
            self.memoryUsage = memoryUsage
            self.action = action
        }
    }

    private var memoryEvents: [MemoryEvent] = []
    private let maxEventsToKeep = 100

    public init() {
        // Save original cache config to restore later
        self.originalCache = URLCache.shared
        setupMemoryMonitoring()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func stop() {
        memoryCheckTimer?.invalidate()
        memoryCheckTimer = nil
        // Restore original URLCache settings
        URLCache.shared.memoryCapacity = originalCache.memoryCapacity
        URLCache.shared.diskCapacity = originalCache.diskCapacity
    }

    private func setupMemoryMonitoring() {
        // Monitor memory warnings from the system
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: NSNotification.Name("NSApplicationDidReceiveMemoryWarning"),
            object: nil
        )

        // Start periodic memory checks
        memoryCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkMemoryUsage()
            }
        }

        // Initial check
        checkMemoryUsage()
    }

    @objc private func handleMemoryWarning() {
        Task { @MainActor in
            memoryWarningCount += 1
            memoryPressure = .critical
            logMemoryEvent(level: .critical, action: "System memory warning received")

            // Trigger aggressive cleanup
            await performMemoryCleanup(aggressive: true)
        }
    }

    private func checkMemoryUsage() {
        let usage = getMemoryUsage()
        currentMemoryUsage = usage.used

        let usagePercentage = Double(usage.used) / Double(usage.total)

        let previousLevel = memoryPressure

        if usagePercentage >= 0.9 {
            memoryPressure = .critical
        } else if usagePercentage >= memoryWarningThreshold {
            memoryPressure = .warning
        } else {
            memoryPressure = .normal
        }

        // Log level changes
        if memoryPressure != previousLevel {
            logMemoryEvent(level: memoryPressure, action: "Memory pressure changed from \(previousLevel.description) to \(memoryPressure.description)")

            // Trigger cleanup if needed
            if memoryPressure != .normal {
                Task {
                    await performMemoryCleanup(aggressive: memoryPressure == .critical)
                }
            }
        }
    }

    private func getMemoryUsage() -> (used: UInt64, total: UInt64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self(), task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let used = info.resident_size

            // Get total physical memory
            var size: UInt64 = 0
            var sizeLen = MemoryLayout<UInt64>.size
            sysctlbyname("hw.memsize", &size, &sizeLen, nil, 0)

            return (used, size)
        }

        return (0, 0)
    }

    private func performMemoryCleanup(aggressive: Bool) async {
        var actions: [String] = []

        // Clear URL cache
        URLCache.shared.removeAllCachedResponses()
        actions.append("Cleared URL cache")

        // Clear image cache (if we had one)
        // ImageCache.shared.clear()

        if aggressive {
            // More aggressive cleanup
            URLCache.shared.diskCapacity = 0
            URLCache.shared.memoryCapacity = 0
            actions.append("Disabled URL caching")

            // Notify other services to reduce memory usage
            NotificationCenter.default.post(name: .memoryPressureCritical, object: nil)
            actions.append("Notified services of critical memory pressure")
        }

        logMemoryEvent(level: memoryPressure, action: "Performed cleanup: \(actions.joined(separator: ", "))")
    }

    private func logMemoryEvent(level: MemoryPressureLevel, action: String) {
        let event = MemoryEvent(
            timestamp: Date(),
            level: level,
            memoryUsage: currentMemoryUsage,
            action: action
        )

        memoryEvents.append(event)

        // Keep only recent events
        if memoryEvents.count > maxEventsToKeep {
            memoryEvents.removeFirst(memoryEvents.count - maxEventsToKeep)
        }

        // Persist events
        saveMemoryEvents()
    }

    public func getMemoryEvents() -> [MemoryEvent] {
        return memoryEvents
    }

    public func clearMemoryEvents() {
        memoryEvents.removeAll()
        saveMemoryEvents()
    }

    private func saveMemoryEvents() {
        guard let data = try? JSONEncoder().encode(memoryEvents) else { return }
        UserDefaults.standard.set(data, forKey: "memoryEvents")
    }

    private func loadMemoryEvents() {
        guard let data = UserDefaults.standard.data(forKey: "memoryEvents"),
              let events = try? JSONDecoder().decode([MemoryEvent].self, from: data) else {
            return
        }
        memoryEvents = events
    }

    public func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

}
