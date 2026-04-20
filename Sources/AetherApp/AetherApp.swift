import SwiftUI
import SwiftData
import AetherCore
import AetherUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be called before any windows are created — sets app as regular GUI app
        NSApp.setActivationPolicy(.regular)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // Force SwiftUI windows to appear (skip status bar windows)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.windows
                .filter { $0.canBecomeKey }
                .forEach { $0.makeKeyAndOrderFront(nil) }
        }
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

    @State private var epgStore = EPGStore()
    @State private var playerCore = PlayerCore()
    @State private var historyCoordinator = HistoryCoordinator()
    @State private var sleepTimer = SleepTimerService()
    @State private var subtitleStore = SubtitleStore()
    @State private var themeService = ThemeService()
    @State private var parentalService = ParentalControlService()
    @State private var recordingService = RecordingService()
    @State private var timeshiftService = TimeshiftService()
    @State private var trackService = TrackService()
    @State private var miniPlayerController: MiniPlayerWindowController
    @State private var crashReportingService = CrashReportingService()
    @State private var networkMonitor = NetworkMonitorService()
    @State private var offlineQueue: OfflineQueueService
    @State private var memoryMonitor = MemoryMonitorService()
    @State private var analyticsService = AnalyticsService()
    @State private var iCloudSync = iCloudSyncService()
    @State private var statusBarController: StatusBarController

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        let player = PlayerCore()
        let network = NetworkMonitorService()
        let analytics = AnalyticsService()
        _playerCore = State(wrappedValue: player)
        _miniPlayerController = State(wrappedValue: MiniPlayerWindowController(player: player))
        _networkMonitor = State(wrappedValue: network)
        _offlineQueue = State(wrappedValue: OfflineQueueService(networkMonitor: network))
        _analyticsService = State(wrappedValue: analytics)
        _statusBarController = State(wrappedValue: StatusBarController(player: player))

        // Wire analytics to player
        player.onWatchSessionEnd = { channel, startTime, duration in
            Task { @MainActor in
                analytics.recordWatchSession(
                    channelName: channel.name,
                    startTime: startTime,
                    duration: TimeInterval(duration),
                    category: channel.groupTitle
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(playerCore: playerCore)
                .environment(epgStore)
                .environment(playerCore)
                .environment(iCloudSync)
                .environment(sleepTimer)
                .environment(subtitleStore)
                .environment(themeService)
                .environment(parentalService)
                .environment(recordingService)
                .environment(timeshiftService)
                .environment(trackService)
                .environment(miniPlayerController)
                .environment(networkMonitor)
                .environment(offlineQueue)
                .environment(memoryMonitor)
                .environment(analyticsService)
                .task {
                    // Wire watch history once the view (and its modelContext) are ready
                    historyCoordinator.bind(playerCore: playerCore)
                    // Wire sleep timer → stop
                    sleepTimer.onExpired = { [weak playerCore] in
                        playerCore?.stop()
                    }
                    // Setup status bar
                    statusBarController.setup()
                }
                .sheet(isPresented: .constant(!hasCompletedOnboarding)) {
                    OnboardingView(isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { hasCompletedOnboarding = !$0 }
                    ))
                    .interactiveDismissDisabled()
                }
        }
        .modelContainer(AetherApp.sharedModelContainer)
        .defaultSize(width: 1280, height: 800)
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(epgStore)
                .environment(themeService)
                .environment(parentalService)
        }
        #endif
    }
}

// MARK: - Shared SwiftData Container

extension AetherApp {
    /// Explicit store path — stable regardless of bundle ID (SPM dev-build workaround).
    static let sharedModelContainer: ModelContainer = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Aether")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let storeURL = appSupport.appendingPathComponent("aether.store")

        // Purge stale persistent history so CoreData stops logging
        // "Persistent History has to be truncated due to removed entities".
        // This happens when entities were removed+re-added during development.
        purgePersistentHistory(storeURL: storeURL)

        let config = ModelConfiguration(url: storeURL)
        do {
            let container = try ModelContainer(
                for: PlaylistRecord.self, FavoriteRecord.self, WatchHistoryRecord.self,
                migrationPlan: AetherMigrationPlan.self,
                configurations: config
            )
            return container
        } catch {
            print("[Aether] SwiftData store failed (trying without migration): \(error)")
            do {
                let container = try ModelContainer(
                    for: PlaylistRecord.self, FavoriteRecord.self, WatchHistoryRecord.self,
                    configurations: config
                )
                return container
            } catch {
                print("[Aether] SwiftData store failed entirely: \(error) — using in-memory fallback")
                let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
                return try! ModelContainer(
                    for: PlaylistRecord.self, FavoriteRecord.self, WatchHistoryRecord.self,
                    configurations: fallback
                )
            }
        }
    }()

    /// Truncates all persistent history transactions so stale entity-removal
    /// warnings don't appear when SwiftData models are added/removed during dev.
    private static func purgePersistentHistory(storeURL: URL) {
        let mom = NSManagedObjectModel()
        let psc = NSPersistentStoreCoordinator(managedObjectModel: mom)
        let options: [String: Any] = [
            NSPersistentHistoryTrackingKey: true as NSNumber,
            NSPersistentStoreRemoteChangeNotificationPostOptionKey: false as NSNumber
        ]
        guard let store = try? psc.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: options
        ) else { return }
        let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        ctx.persistentStoreCoordinator = psc
        ctx.performAndWait {
            let truncate = NSPersistentHistoryChangeRequest.deleteHistory(before: Date())
            _ = try? ctx.execute(truncate)
        }
        try? psc.remove(store)
    }
}

// MARK: - HistoryCoordinator

/// Bridges `PlayerCore.onWatchSessionEnd` → SwiftData insert.
/// Lives as a @State so it's retained for the app's lifetime.
@MainActor
@Observable
final class HistoryCoordinator {
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
