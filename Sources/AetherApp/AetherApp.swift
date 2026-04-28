import Foundation
import SwiftUI
import Observation
import SwiftData
import AetherCore
import AetherUI

#if os(macOS)
private enum AetherWindowLayout {
    static let minimumContentSize = CGSize(width: 960, height: 640)
    static let preferredContentSize = CGSize(width: 1280, height: 800)
    static let screenMargin: CGFloat = 64
}
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be called before any windows are created - sets app as regular GUI app
        NSApp.setActivationPolicy(.regular)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // Force SwiftUI windows to appear (skip status bar windows)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
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
    @State private var playerCore: PlayerCore
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
    @State private var networkMonitor: NetworkMonitorService
    @State private var offlineQueue: OfflineQueueService
    @State private var memoryMonitor = MemoryMonitorService()
    @State private var analyticsService: AnalyticsService
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

        Self.configureImageURLCache()

        // Wire analytics to player without taking ownership of the single legacy callback.
        player.addWatchSessionEndObserver { channel, startTime, duration in
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
                    // Wire shared EPGStore into mini player window (it creates its own NSWindow)
                    miniPlayerController.epgStore = epgStore
                    // Wire watch history once the view (and its modelContext) are ready
                    historyCoordinator.bind(playerCore: playerCore)
                    // Wire sleep timer -> stop
                    sleepTimer.onExpired = { [weak playerCore] in
                        playerCore?.stop()
                    }
                    // Setup status bar
                    statusBarController.setup()
                    // Request notification authorization once at startup
                    guard Bundle.main.bundleIdentifier != nil else { return }
                    Task { await NotificationManager.shared.requestAuthorization() }
                }
                .sheet(isPresented: .constant(!hasCompletedOnboarding)) {
                    OnboardingView(isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { hasCompletedOnboarding = !$0 }
                    ))
                    .interactiveDismissDisabled()
                }
                #if os(macOS)
                .frame(
                    minWidth: AetherWindowLayout.minimumContentSize.width,
                    minHeight: AetherWindowLayout.minimumContentSize.height
                )
                .background(AetherWindowConfigurator())
                #endif
        }
        .modelContainer(AetherApp.sharedModelContainer)
        .defaultSize(width: 1280, height: 800)
        #if os(macOS)
        .windowResizability(.automatic)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandMenu("Odtwarzacz") {
                Button("Odtwarzaj / Pauza") {
                    playerCore.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Stop") {
                    playerCore.stop()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Divider()

                Button("Next Channel") {
                    playerCore.playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Previous Channel") {
                    playerCore.playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Szukaj...") {
                    NotificationCenter.default.post(name: .aetherNavigateSearch, object: nil)
                    NotificationCenter.default.post(name: .init("AetherOpenSearch"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu("Nawigacja") {
                Button("Ulubione") {
                    NotificationCenter.default.post(name: .aetherNavigateFavorites, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Wyszukaj") {
                    NotificationCenter.default.post(name: .aetherNavigateSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Historia") {
                    NotificationCenter.default.post(name: .aetherNavigateHistory, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("EPG / Live TV") {
                    NotificationCenter.default.post(name: .aetherNavigateLive, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandMenu("Konto") {
                Button("Refresh Channel List") {
                    NotificationCenter.default.post(name: .aetherRefreshPlaylist, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(epgStore)
                .environment(themeService)
                .environment(parentalService)
                .environment(analyticsService)
        }
        #endif
    }
}

#if os(macOS)
private struct AetherWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView(frame: .zero)
        let coordinator = context.coordinator
        view.onWindowAvailable = { window in
            coordinator.configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        let coordinator = context.coordinator
        nsView.onWindowAvailable = { window in
            coordinator.configure(window)
        }
        if let window = nsView.window {
            coordinator.configure(window)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class WindowProbeView: NSView {
        var onWindowAvailable: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindowAvailable?(window)
            }
        }
    }

    final class Coordinator {
        private weak var configuredWindow: NSWindow?

        func configure(_ window: NSWindow) {
            guard configuredWindow !== window else { return }
            configuredWindow = window

            window.contentMinSize = AetherWindowLayout.minimumContentSize

            guard !window.styleMask.contains(.fullScreen) else { return }
            let currentSize = window.contentLayoutRect.size
            let minimumSize = AetherWindowLayout.minimumContentSize
            guard currentSize.width < minimumSize.width || currentSize.height < minimumSize.height else { return }

            window.setContentSize(Self.clampedPreferredContentSize(for: window))
            window.center()
        }

        private static func clampedPreferredContentSize(for window: NSWindow) -> NSSize {
            let preferredSize = AetherWindowLayout.preferredContentSize
            let minimumSize = AetherWindowLayout.minimumContentSize
            guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
                return preferredSize
            }

            let availableWidth = max(minimumSize.width, visibleFrame.width - AetherWindowLayout.screenMargin)
            let availableHeight = max(minimumSize.height, visibleFrame.height - AetherWindowLayout.screenMargin)

            return NSSize(
                width: min(preferredSize.width, availableWidth),
                height: min(preferredSize.height, availableHeight)
            )
        }
    }
}
#endif

// MARK: - Shared SwiftData Container

extension AetherApp {
    private static let imageURLCacheMemoryCapacity = 100 * 1024 * 1024
    private static let imageURLCacheDiskCapacity = 500 * 1024 * 1024
    private static let playlistBackupKey = "playlist_backup_v7"

    private static func configureImageURLCache() {
        URLCache.shared = URLCache(
            memoryCapacity: imageURLCacheMemoryCapacity,
            diskCapacity: imageURLCacheDiskCapacity,
            directory: imageURLCacheDirectory()
        )
    }

    private static func imageURLCacheDirectory() -> URL? {
        do {
            let baseURL = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = baseURL
                .appendingPathComponent("Aether", isDirectory: true)
                .appendingPathComponent("ImageCache", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            print("[Aether] Failed to prepare image URL cache directory: \(error.localizedDescription)")
            return nil
        }
    }

    /// Explicit store path — stable regardless of bundle ID (SPM dev-build workaround).
    static let sharedModelContainer: ModelContainer = {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            preconditionFailure("[Aether] No ApplicationSupport directory — system is unrecoverable")
        }
        let appSupport = base.appendingPathComponent("Aether")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let storeURL = appSupport.appendingPathComponent("aether.store")

        // Delete the store if it was created with an incompatible schema (CoreData 134100).
        // This happens when entities were added/removed during development.
        resetStoreIfIncompatible(storeURL: storeURL)

        let config = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(
                for: PlaylistRecord.self, FavoriteRecord.self, WatchHistoryRecord.self,
                migrationPlan: AetherMigrationPlan.self,
                configurations: config
            )
            restorePlaylistBackupIfNeeded(context: container.mainContext)
            return container
        } catch {
            print("[Aether] SwiftData store failed (trying without migration): \(error)")
            do {
                let container = try ModelContainer(
                    for: PlaylistRecord.self, FavoriteRecord.self, WatchHistoryRecord.self,
                    configurations: config
                )
                restorePlaylistBackupIfNeeded(context: container.mainContext)
                return container
            } catch {
                print("[Aether] SwiftData store failed entirely: \(error) — using in-memory fallback")
                let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(
                        for: PlaylistRecord.self, FavoriteRecord.self, WatchHistoryRecord.self,
                        configurations: fallback
                    )
                } catch let fallbackError {
                    preconditionFailure("[Aether] In-memory ModelContainer failed — unrecoverable: \(fallbackError)")
                }
            }
        }
    }()

    /// Removes the SQLite store only when metadata proves it is incompatible with the current schema.
    /// Prevents NSCocoaErrorDomain 134100 without doing a version-flag destructive reset.
    private static func resetStoreIfIncompatible(storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let metadata: [String: Any]
        do {
            metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: storeURL, options: nil)
        } catch {
            backupPlaylistsIfPossible(storeURL: storeURL)
            removeStore(at: storeURL)
            print("[AetherDB] Removed unreadable store, will recreate")
            return
        }

        // Current schema only has PlaylistRecord, FavoriteRecord, WatchHistoryRecord.
        // If the on-disk store has extra entities from an old schema, the hashes won't match.
        let storeHashes = metadata["NSStoreModelVersionHashes"] as? [String: Any] ?? [:]
        let knownEntities: Set<String> = ["PlaylistRecord", "FavoriteRecord", "WatchHistoryRecord"]
        let storeEntities = Set(storeHashes.keys)
        let unknownEntities = storeEntities.subtracting(knownEntities)

        if !unknownEntities.isEmpty {
            backupPlaylistsIfPossible(storeURL: storeURL)
            removeStore(at: storeURL)
            print("[AetherDB] Removed incompatible store (unknown entities: \(unknownEntities)), will recreate")
        }
    }

    private static func backupPlaylistsIfPossible(storeURL: URL) {
        let backups = backupPlaylistsFromStore(storeURL: storeURL)
        if !backups.isEmpty {
            UserDefaults.standard.set(backups, forKey: playlistBackupKey)
            print("[AetherDB] Backed up \(backups.count) playlist(s) before incompatible store reset")
        }
    }

    /// Read raw playlist rows from SQLite before wiping the store.
    /// Returns array of dicts with all PlaylistRecord fields.
    private static func backupPlaylistsFromStore(storeURL: URL) -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        var backups: [[String: Any]] = []

        // Use low-level NSPersistentStoreCoordinator with an empty model to read raw rows
        // Actually simpler: use GRDB-free approach via NSPersistentContainer with the old store.
        // Since SwiftData uses SQLite underneath, we attempt a temporary NSPersistentContainer.
        // If the schema mismatch prevents loading, we read nothing (safe — playlist already lost).
        let managedModel = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "PlaylistRecord"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        func attr(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let d = NSAttributeDescription()
            d.name = name
            d.attributeType = type
            d.isOptional = true
            return d
        }

        entity.properties = [
            attr("name", .stringAttributeType),
            attr("urlString", .stringAttributeType),
            attr("playlistTypeRaw", .stringAttributeType),
            attr("xstreamHost", .stringAttributeType),
            attr("xstreamUsername", .stringAttributeType),
            attr("xstreamPassword", .stringAttributeType),
            attr("epgURLString", .stringAttributeType),
            attr("sortIndex", .integer64AttributeType),
        ]
        managedModel.entities = [entity]

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: managedModel)
        let options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: false,
            NSInferMappingModelAutomaticallyOption: false,
            NSSQLiteAnalyzeOption: false,
        ]
        guard (try? coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: options
        )) != nil else { return [] }

        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = coordinator
        let req = NSFetchRequest<NSManagedObject>(entityName: "PlaylistRecord")
        guard let results = try? ctx.fetch(req) else { return [] }

        for obj in results {
            var dict: [String: Any] = [:]
            for key in ["name", "urlString", "playlistTypeRaw", "xstreamHost",
                        "xstreamUsername", "xstreamPassword", "epgURLString", "sortIndex"] {
                if let val = obj.value(forKey: key) {
                    dict[key] = val
                }
            }
            backups.append(dict)
        }
        return backups
    }

    /// Re-inserts playlist records from the UserDefaults backup into a fresh ModelContext.
    /// Call this after the ModelContainer is created, once, and then clear the backup.
    static func restorePlaylistBackupIfNeeded(context: ModelContext) {
        guard let backups = UserDefaults.standard.array(forKey: playlistBackupKey) as? [[String: Any]],
              !backups.isEmpty else { return }

        print("[AetherDB] Restoring \(backups.count) playlist(s) from backup")
        for dict in backups {
            let name = dict["name"] as? String ?? ""
            let urlString = dict["urlString"] as? String ?? ""
            let typeRaw = dict["playlistTypeRaw"] as? String ?? "m3u"
            let sortIndex = dict["sortIndex"] as? Int ?? 0
            let record = PlaylistRecord(
                name: name,
                urlString: urlString,
                sortIndex: sortIndex,
                playlistType: PlaylistType(rawValue: typeRaw) ?? .m3u,
                xstreamHost: dict["xstreamHost"] as? String,
                xstreamUsername: dict["xstreamUsername"] as? String,
                xstreamPassword: dict["xstreamPassword"] as? String,
                epgURLString: dict["epgURLString"] as? String
            )
            context.insert(record)
        }
        try? context.save()
        UserDefaults.standard.removeObject(forKey: playlistBackupKey)
        print("[AetherDB] Playlist restore complete")
    }

    private static func removeStore(at storeURL: URL) {
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
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
    @ObservationIgnored private var watchSessionObserverID: UUID?
    @ObservationIgnored private var progressObserverID: UUID?

    func bind(playerCore: PlayerCore) {
        guard !isBound else { return }
        isBound = true
        // Use the shared container so watch history lands in the same store the app reads from.
        // Previously created a new ModelContainer (default path) which caused history to be
        // written to a different database than AetherApp.sharedModelContainer.
        let ctx = ModelContext(AetherApp.sharedModelContainer)
        self.modelContext = ctx

        watchSessionObserverID = playerCore.addWatchSessionEndObserver { [weak self] channel, watchedAt, duration in
            guard let ctx = self?.modelContext else { return }
            let record = Self.upsertHistoryRecord(
                for: channel,
                watchedAt: watchedAt,
                durationSeconds: duration,
                context: ctx
            )
            if record.totalDurationSeconds <= 0 {
                record.totalDurationSeconds = Double(duration)
            }
            record.durationSeconds = max(record.durationSeconds, duration)
            Self.trimHistory(context: ctx)
            try? ctx.save()
        }

        progressObserverID = playerCore.addProgressUpdateObserver { [weak self] channel, watched, total in
            guard let ctx = self?.modelContext else { return }
            let record = Self.upsertHistoryRecord(
                for: channel,
                watchedAt: .now,
                durationSeconds: Int(watched),
                context: ctx
            )
            record.watchedSecondsDouble = watched
            record.totalDurationSeconds = total
            record.durationSeconds = max(record.durationSeconds, Int(watched))
            try? ctx.save()
        }
    }

    private static func upsertHistoryRecord(
        for channel: Channel,
        watchedAt: Date,
        durationSeconds: Int,
        context: ModelContext
    ) -> WatchHistoryRecord {
        if let existing = existingHistoryRecord(for: channel, context: context) {
            existing.channelName = channel.name
            existing.streamURLString = channel.streamURL.absoluteString
            existing.logoURLString = channel.logoURL?.absoluteString
            existing.groupTitle = channel.groupTitle
            existing.epgId = channel.epgId
            existing.watchedAt = watchedAt
            existing.durationSeconds = max(existing.durationSeconds, durationSeconds)
            existing.contentType = channel.contentType == .movie ? "movie"
                : channel.contentType == .series ? "series"
                : "live"
            return existing
        }

        let record = WatchHistoryRecord(
            channel: channel,
            watchedAt: watchedAt,
            durationSeconds: durationSeconds
        )
        context.insert(record)
        return record
    }

    private static func existingHistoryRecord(for channel: Channel, context: ModelContext) -> WatchHistoryRecord? {
        let descriptor = FetchDescriptor<WatchHistoryRecord>(
            sortBy: [SortDescriptor(\.watchedAt, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor) else { return nil }
        return records.first {
            $0.channelID == channel.id || $0.streamURLString == channel.streamURL.absoluteString
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
        try? context.save()
    }
}
