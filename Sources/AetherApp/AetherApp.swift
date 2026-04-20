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

        // Aggressive image caching — 100MB memory, 500MB disk
        URLCache.shared = URLCache(
            memoryCapacity: 100 * 1024 * 1024,
            diskCapacity: 500 * 1024 * 1024,
            diskPath: "aether_image_cache"
        )

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

        // Delete the store if it was created with an incompatible schema (CoreData 134100).
        // This happens when entities were added/removed during development.
        resetStoreIfIncompatible(storeURL: storeURL)

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

    /// Removes the SQLite store if it contains entities that no longer exist in the current schema.
    /// Prevents NSCocoaErrorDomain 134100 (incompatible model) on first launch after a schema change.
    private static func resetStoreIfIncompatible(storeURL: URL) {
        // Nuclear reset (v5): wipe all store files once after schema overhaul
        let resetKey = "store_reset_v5"
        if !UserDefaults.standard.bool(forKey: resetKey) {
            let appSupport = storeURL.deletingLastPathComponent()
            let fm = FileManager.default
            if let items = try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) {
                for item in items {
                    let ext = item.pathExtension.lowercased()
                    let base = item.deletingPathExtension().lastPathComponent.lowercased()
                    if ["sqlite", "store", "wal", "shm"].contains(ext)
                        || base.hasSuffix("-wal") || base.hasSuffix("-shm") {
                        try? fm.removeItem(at: item)
                    }
                }
            }
            // Also delete WAL/SHM suffixed variants (aether.store-wal, aether.store-shm)
            let storeWAL = storeURL.appendingPathExtension("-wal")
            let storeSHM = storeURL.appendingPathExtension("-shm")
            try? fm.removeItem(at: storeWAL)
            try? fm.removeItem(at: storeSHM)
            UserDefaults.standard.set(true, forKey: resetKey)
            print("[AetherDB] Nuclear store reset (v5) complete")
            return
        }

        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let metadata: [String: Any]
        do {
            metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: storeURL, options: nil)
        } catch {
            // Unreadable store — remove it and let SwiftData recreate
            removeStore(at: storeURL)
            print("[AetherDB] Removed unreadable store, will recreate")
            return
        }

        // Current schema only has PlaylistRecord, FavoriteRecord, WatchHistoryRecord.
        // If the on-disk store has extra entities from an old schema, the hashes won't match.
        let storeHashes = metadata["NSStoreModelVersionHashes"] as? [String: Any] ?? [:]
        let knownEntities: Set<String> = ["PlaylistRecord", "FavoriteRecord", "WatchHistoryRecord",
                                          "ChannelRecord", "MovieRecord", "SeriesRecord",
                                          "WatchProgressRecord"]
        let storeEntities = Set(storeHashes.keys)
        let unknownEntities = storeEntities.subtracting(knownEntities)

        if !unknownEntities.isEmpty {
            removeStore(at: storeURL)
            print("[AetherDB] Removed incompatible store (unknown entities: \(unknownEntities)), will recreate")
        }
    }

    private static func removeStore(at storeURL: URL) {
        let walURL = storeURL.appendingPathExtension("wal")
        let shmURL = storeURL.appendingPathExtension("shm")
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: walURL)
        try? FileManager.default.removeItem(at: shmURL)
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
