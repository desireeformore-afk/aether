import SwiftUI
import SwiftData
import AetherCore
import AetherUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct AetherApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var epgStore = EPGStore()
    @StateObject private var playerCore = PlayerCore()
    @StateObject private var historyCoordinator = HistoryCoordinator()
    @StateObject private var sleepTimer = SleepTimerService()
    @StateObject private var subtitleStore = SubtitleStore()
    @StateObject private var themeService = ThemeService()
    @StateObject private var parentalService = ParentalControlService()
    @StateObject private var recordingService = RecordingService()
    @StateObject private var timeshiftService = TimeshiftService()
    @StateObject private var trackService = TrackService()
    @StateObject private var miniPlayerController: MiniPlayerWindowController
    @StateObject private var crashReportingService = CrashReportingService()
    @StateObject private var networkMonitor = NetworkMonitorService()
    @StateObject private var offlineQueue: OfflineQueueService

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        let player = PlayerCore()
        let network = NetworkMonitorService()
        _playerCore = StateObject(wrappedValue: player)
        _miniPlayerController = StateObject(wrappedValue: MiniPlayerWindowController(player: player))
        _networkMonitor = StateObject(wrappedValue: network)
        _offlineQueue = StateObject(wrappedValue: OfflineQueueService(networkMonitor: network))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(playerCore: playerCore)
                .environmentObject(epgStore)
                .environmentObject(playerCore)
                .environmentObject(sleepTimer)
                .environmentObject(subtitleStore)
                .environmentObject(themeService)
                .environmentObject(parentalService)
                .environmentObject(recordingService)
                .environmentObject(timeshiftService)
                .environmentObject(trackService)
                .environmentObject(miniPlayerController)
                .environmentObject(networkMonitor)
                .environmentObject(offlineQueue)
                .task {
                    // Wire watch history once the view (and its modelContext) are ready
                    historyCoordinator.bind(playerCore: playerCore)
                    // Wire sleep timer → stop
                    sleepTimer.onExpired = { [weak playerCore] in
                        playerCore?.stop()
                    }
                }
                .sheet(isPresented: .constant(!hasCompletedOnboarding)) {
                    OnboardingView(isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { hasCompletedOnboarding = !$0 }
                    ))
                    .interactiveDismissDisabled()
                }
        }
        .modelContainer(for: [
            PlaylistRecord.self,
            FavoriteRecord.self,
            WatchHistoryRecord.self,
        ])

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(epgStore)
                .environmentObject(themeService)
                .environmentObject(parentalService)
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
