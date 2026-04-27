import Foundation
import Observation
import Combine

/// Available sleep timer durations.
public enum SleepTimerDuration: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes  = 30
    case fortyFiveMinutes = 45
    case oneHour        = 60
    case ninetyMinutes  = 90
    case twoHours       = 120

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .fifteenMinutes:  return "15 min"
        case .thirtyMinutes:   return "30 min"
        case .fortyFiveMinutes: return "45 min"
        case .oneHour:         return "1 hour"
        case .ninetyMinutes:   return "1.5 hours"
        case .twoHours:        return "2 hours"
        }
    }

    /// Duration in seconds.
    public var seconds: TimeInterval { TimeInterval(rawValue * 60) }
}

/// Manages an auto-stop timer for the player.
/// When the timer fires, calls `onExpired` (set by the caller — typically `playerCore.stop()`).
@MainActor
@Observable
public final class SleepTimerService {

    // MARK: - Published

    public private(set) var isActive: Bool = false
    public private(set) var remainingSeconds: Int = 0

    // MARK: - Callback

    /// Called when the timer expires. Set this to `playerCore.stop`.
    public var onExpired: (() -> Void)?

    // MARK: - Private

    private var endDate: Date?
    private var tickCancellable: AnyCancellable?

    public init() {}

    // MARK: - API

    /// Starts or resets the sleep timer for the given duration.
    public func start(duration: SleepTimerDuration) { set(duration) }

    /// Starts or resets the sleep timer for the given duration.
    public func set(_ duration: SleepTimerDuration) {
        cancel()
        let end = Date.now.addingTimeInterval(duration.seconds)
        endDate = end
        remainingSeconds = duration.rawValue * 60
        isActive = true

        // Tick every second on the main run loop
        tickCancellable = Timer
            .publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.tick() }
            }
    }

    /// Cancels the active sleep timer.
    public func cancel() {
        tickCancellable = nil
        isActive = false
        remainingSeconds = 0
        endDate = nil
    }

    // MARK: - Private

    private func tick() {
        guard let end = endDate else { return }
        let remaining = Int(end.timeIntervalSinceNow.rounded(.up))
        if remaining <= 0 {
            cancel()
            onExpired?()
        } else {
            remainingSeconds = remaining
        }
    }
}

// MARK: - Helpers

extension SleepTimerService {
    /// Human-readable countdown string (e.g. "29:45").
    public var remainingFormatted: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Human-readable countdown string (e.g. "29:45").
    public var countdownString: String { remainingFormatted }
}
