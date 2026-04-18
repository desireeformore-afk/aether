import Foundation

/// Background EPG refresh service that periodically updates EPG data.
@MainActor
public final class BackgroundEPGRefreshService: ObservableObject {
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var lastRefreshDate: Date?
    @Published public private(set) var nextRefreshDate: Date?

    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval
    private weak var epgStore: EPGStore?

    public init(refreshInterval: TimeInterval = 3600, epgStore: EPGStore? = nil) {
        self.refreshInterval = refreshInterval
        self.epgStore = epgStore
    }

    /// Starts background EPG refresh.
    public func start() {
        guard !isEnabled else { return }
        isEnabled = true
        scheduleNextRefresh()
    }

    /// Stops background EPG refresh.
    public func stop() {
        isEnabled = false
        refreshTask?.cancel()
        refreshTask = nil
        nextRefreshDate = nil
    }

    /// Manually triggers an immediate refresh.
    public func refreshNow() async {
        guard let epgStore, let url = epgStore.currentEPGURL else { return }
        await epgStore.loadGuide(from: url, forceRefresh: true)
        lastRefreshDate = Date()
        if isEnabled {
            scheduleNextRefresh()
        }
    }

    // MARK: - Private

    private func scheduleNextRefresh() {
        refreshTask?.cancel()

        let nextRefresh = Date().addingTimeInterval(refreshInterval)
        nextRefreshDate = nextRefresh

        refreshTask = Task { [weak self] in
            guard let self else { return }

            // Wait until next refresh time
            let delay = nextRefresh.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }

            guard !Task.isCancelled, self.isEnabled else { return }

            // Perform refresh
            await self.refreshNow()
        }
    }
}
