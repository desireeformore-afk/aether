import SwiftUI
import SwiftData
import AetherCore

@main
struct AetherApp: App {
    @StateObject private var epgStore = EPGStore()
    @StateObject private var playerCore = PlayerCore()
    @StateObject private var historyCoordinator = HistoryCoordinator()
    @StateObject private var sleepTimer = SleepTimerService()
    @StateObject private var subtitleStore = SubtitleStore()

    var body: some Scene {
        WindowGroup {
            ContentView(playerCore: playerCore)
                .environmentObject(epgStore)
                .environmentObject(playerCore)
                .environmentObject(sleepTimer)
                .environmentObject(subtitleStore)
                .task {
                    // Wire watch history once the view (and its modelContext) are ready
                    historyCoordinator.bind(playerCore: playerCore)
                    // Wire sleep timer → stop
                    sleepTimer.onExpired = { [weak playerCore] in
                        playerCore?.stop()
                    }
                }
        }
        .modelContainer(for: [
            PlaylistRecord.self,
            ChannelRecord.self,
            FavoriteRecord.self,
            WatchHistoryRecord.self,
        ])

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(epgStore)
        }
        #endif
    }
}

// MARK: - HistoryCoordinator

/// Bridges `PlayerCore.onWatchSessionEnd` → SwiftData insert.
/// Lives as a @StateObject so it's retained for the app's lifetime.
@MainActor
final class HistoryCoordinator: ObservableObject {
    private var modelContext: ModelContext?
    private var isBound = false

    func bind(playerCore: PlayerCore) {
        guard !isBound else { return }
        isBound = true
        // Build a background ModelContext using the shared container
        guard let container = try? ModelContainer(for:
            PlaylistRecord.self,
            ChannelRecord.self,
            FavoriteRecord.self,
            WatchHistoryRecord.self
        ) else { return }
        let ctx = ModelContext(container)
        self.modelContext = ctx

        playerCore.onWatchSessionEnd = { [weak self] channel, watchedAt, duration in
            guard let ctx = self?.modelContext else { return }
            let record = WatchHistoryRecord(
                channel: channel,
                watchedAt: watchedAt,
                durationSeconds: duration
            )
            ctx.insert(record)
            Self.trimHistory(context: ctx)
        }
    }

    /// Keeps history to the 200 most recent entries.
    private static func trimHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<WatchHistoryRecord>(
            sortBy: [SortDescriptor(\.watchedAt, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > 200 else { return }
        for old in all.dropFirst(200) {
            context.delete(old)
        }
    }
}
