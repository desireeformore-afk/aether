import SwiftUI
import SwiftData
import AetherCore
import AetherUI
import AppKit

/// App Settings panel — accessible via ⌘, / Aether > Settings…
struct SettingsView: View {
    @Environment(EPGStore.self) private var epgStore
    @Environment(ThemeService.self) private var themeService
    @Environment(\.modelContext) private var modelContext
    @Query private var playlists: [PlaylistRecord]

    // MARK: - UserDefaults-backed preferences

    @AppStorage("epgRefreshInterval") private var epgRefreshInterval: Double = 3600
    @AppStorage("defaultStreamQuality") private var defaultStreamQuality: String = StreamQuality.auto.rawValue
    @AppStorage("useHardwareDecoding") private var useHardwareDecoding = true
    @AppStorage("preferredBufferDuration") private var preferredBufferDuration: Int = 30
    @AppStorage("preferredColorScheme") private var preferredColorScheme: String = "auto"
    @AppStorage("preferredLanguage") private var preferredLanguage: String = "pl"
    @AppStorage("preferredCountry") private var preferredCountry: String = "PL"

    // MARK: - Local UI state

    @State private var showClearConfirm = false
    @State private var cacheSize: String = "Calculating…"
    @State private var showExportSheet = false
    @State private var showImportSheet = false
    @State private var exportMessage: String?
    @State private var importMessage: String?

    // Account tab
    @State private var showAddPlaylistSheet = false

    // Advanced tab
    @State private var showResetHistoryConfirm = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Ogólne", systemImage: "gearshape") }

            playerTab
                .tabItem { Label("Odtwarzacz", systemImage: "play.circle") }
                .tag("player")

            accountTab
                .tabItem { Label("Konto", systemImage: "person.circle") }
                .tag("account")

            playlistTab
                .tabItem { Label("Playlisty", systemImage: "list.bullet") }
                .tag("playlists")

            epgTab
                .tabItem { Label("EPG", systemImage: "calendar") }
                .tag("epg")

            cacheTab
                .tabItem { Label("Cache", systemImage: "internaldrive") }
                .tag("cache")

            SubtitleSettingsView()
                .tabItem { Label("Napisy", systemImage: "captions.bubble") }
                .tag("subtitles")

            appearanceTab
                .tabItem { Label("Wygląd", systemImage: "paintbrush") }
                .tag("appearance")

            parentalControlsTab
                .tabItem { Label("Kontrola", systemImage: "lock.shield") }
                .tag("parental")

            analyticsTab
                .tabItem { Label("Analityka", systemImage: "chart.bar") }
                .tag("analytics")

            iCloudSyncView()
                .tabItem { Label("iCloud", systemImage: "icloud") }
                .tag("icloud")

            advancedTab
                .tabItem { Label("Zaawansowane", systemImage: "gearshape.2") }
                .tag("advanced")

            aboutTab
                .tabItem { Label("O aplikacji", systemImage: "info.circle") }
                .tag("about")
        }
        .padding(20)
        .frame(width: 520)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Zamknij") { NSApp.keyWindow?.close() }
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
        .onAppear { refreshCacheSize() }
    }

    // MARK: - General Tab

    private let languages: [(code: String, label: String)] = [
        ("pl", "🇵🇱 Polski"),
        ("en", "🇺🇸 English"),
        ("tr", "🇹🇷 Türkçe"),
        ("de", "🇩🇪 Deutsch"),
        ("fr", "🇫🇷 Français"),
        ("es", "🇪🇸 Español"),
        ("ar", "🇸🇦 العربية"),
    ]

    private let countries: [(code: String, label: String)] = [
        ("PL", "🇵🇱 Polska"),
        ("US", "🇺🇸 United States"),
        ("TR", "🇹🇷 Türkiye"),
        ("DE", "🇩🇪 Deutschland"),
        ("FR", "🇫🇷 France"),
        ("ES", "🇪🇸 España"),
        ("AR", "🇸🇦 Arabia"),
    ]

    private var generalTab: some View {
        Form {
            Section("Język interfejsu") {
                Picker("Język", selection: $preferredLanguage) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                Picker("Kraj / Region", selection: $preferredCountry) {
                    ForEach(countries, id: \.code) { country in
                        Text(country.label).tag(country.code)
                    }
                }
            }
            Section("Motyw") {
                Picker("Schemat kolorów", selection: $preferredColorScheme) {
                    Text("Systemowy").tag("auto")
                    Text("Ciemny").tag("dark")
                    Text("Jasny").tag("light")
                }
                .pickerStyle(.segmented)
                .help("Zmiana jest widoczna natychmiast — nie wymaga restartu.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Player Tab

    private var playerTab: some View {
        Form {
            Section("Jakość strumienia") {
                Picker("Domyślna jakość", selection: $defaultStreamQuality) {
                    ForEach(StreamQuality.allCases, id: \.rawValue) { q in
                        Text(q.displayName).tag(q.rawValue)
                    }
                }
                Toggle("Dekodowanie sprzętowe", isOn: $useHardwareDecoding)
                    .help("Włącz dekodowanie wideo przez GPU / Apple Silicon.")
            }
            Section("Buforowanie") {
                Picker("Bufor wstępny", selection: $preferredBufferDuration) {
                    Text("30 sekund").tag(30)
                    Text("60 sekund").tag(60)
                    Text("120 sekund").tag(120)
                }
                .help("Czas wyprzedzenia bufora AVPlayer dla strumieniowania na żywo.")
            }
            Section("Preferowane ścieżki") {
                Text("Ścieżkę audio i napisy wybierz podczas odtwarzania, klikając ikonę ścieżki na pasku narzędzi odtwarzacza.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Account Tab

    private var accountTab: some View {
        Form {
            Section {
                ForEach(playlists) { playlist in
                    AccountPlaylistRow(playlist: playlist)
                }
                .onDelete { offsets in
                    for i in offsets {
                        modelContext.delete(playlists[i])
                    }
                    try? modelContext.save()
                }
            } header: {
                HStack {
                    Text("Konta / Playlisty (\(playlists.count))")
                    Spacer()
                    Button {
                        showAddPlaylistSheet = true
                    } label: {
                        Label("Dodaj", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } footer: {
                Text("Przesuń w lewo, aby usunąć. Kliknij "+" aby dodać nowe konto M3U lub Xtream Codes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if playlists.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Brak kont",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Dodaj playlistę M3U lub konto Xtream Codes")
                    )
                    .frame(height: 120)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddPlaylistSheet) {
            AddPlaylistSheet { record in
                record.sortIndex = (playlists.last?.sortIndex ?? -1) + 1
            }
        }
    }

    // MARK: - Playlist Tab

    private var playlistTab: some View {
        Form {
            Section("Import / Export") {
                Button("Eksportuj playlistę do M3U…") {
                    exportPlaylist()
                }
                .help("Eksportuj aktualną playlistę do pliku M3U.")

                Button("Importuj plik M3U…") {
                    importPlaylist()
                }
                .help("Importuj kanały z pliku M3U.")
            }

            if let message = exportMessage {
                Section("Status eksportu") {
                    Text(message)
                        .foregroundStyle(message.contains("Error") || message.contains("Błąd") ? Color.red : Color.green)
                        .font(.aetherCaption)
                }
            }

            if let message = importMessage {
                Section("Status importu") {
                    Text(message)
                        .foregroundStyle(message.contains("Error") || message.contains("Błąd") ? Color.red : Color.green)
                        .font(.aetherCaption)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - EPG Tab

    private var epgTab: some View {
        Form {
            Section("Odświeżanie") {
                Picker("Interwał odświeżania EPG", selection: $epgRefreshInterval) {
                    Text("Co 30 minut").tag(1800.0)
                    Text("Co godzinę").tag(3600.0)
                    Text("Co 6 godzin").tag(21600.0)
                    Text("Co 12 godzin").tag(43200.0)
                    Text("Nigdy").tag(0.0)
                }

                Toggle("Automatyczne odświeżanie w tle", isOn: Binding(
                    get: { epgRefreshInterval > 0 },
                    set: { enabled in
                        if !enabled {
                            epgRefreshInterval = 0
                        } else if epgRefreshInterval == 0 {
                            epgRefreshInterval = 3600
                        }
                    }
                ))
                .help("Automatycznie odświeżaj dane EPG w tle.")

                Button("Odśwież teraz") {
                    Task { await epgStore.loadGuide(from: epgStore.currentEPGURL ?? URL(string: "about:blank")!, forceRefresh: true) }
                }
                .disabled(epgStore.currentEPGURL == nil)
                .help("Wymuś natychmiastowe pobranie EPG z aktualnego źródła.")
            }

            Section("Status") {
                LabeledContent("Źródło EPG") {
                    Text(epgStore.currentEPGURL?.host() ?? "Brak")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if epgStore.isLoading {
                    LabeledContent("") {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                if let err = epgStore.lastError {
                    LabeledContent("Ostatni błąd") {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.aetherCaption)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Cache Tab

    private var cacheTab: some View {
        Form {
            Section("Zużycie dysku") {
                LabeledContent("Rozmiar cache", value: cacheSize)

                Button("Wyczyść cache EPG…", role: .destructive) {
                    showClearConfirm = true
                }
                .confirmationDialog(
                    "Wyczyścić cache EPG?",
                    isPresented: $showClearConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Wyczyść cache", role: .destructive) {
                        Task {
                            await epgStore.clearCache()
                            refreshCacheSize()
                        }
                    }
                    Button("Anuluj", role: .cancel) {}
                } message: {
                    Text("Usuwa zapisane dane EPG. Zostaną ponownie pobrane przy następnym odświeżeniu.")
                }
            }

            Section("Cache logo") {
                LabeledContent("Cache obrazów") {
                    Text(logosCacheDescription)
                        .foregroundStyle(.secondary)
                }
                Button("Wyczyść cache logo") {
                    URLCache.shared.removeAllCachedResponses()
                    refreshCacheSize()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshCacheSize() }
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AppearancePickerView()
                    .padding(.bottom, 4)

                Divider()

                ThemePickerView()
                    .environment(themeService)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Parental Controls Tab

    @Environment(ParentalControlService.self) private var parentalService

    private var parentalControlsTab: some View {
        ParentalControlsView(service: parentalService)
    }

    // MARK: - Analytics Tab

    @Environment(AnalyticsService.self) private var analyticsService
    @State private var showAnalytics = false

    private var analyticsTab: some View {
        Form {
            Section("Statystyki oglądania") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Łączny czas oglądania")
                            .font(.body)
                        Text(formatDuration(analyticsService.viewingStats.totalWatchTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Szczegóły") { showAnalytics = true }
                        .buttonStyle(.bordered)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Liczba sesji")
                            .font(.body)
                        Text("\(analyticsService.viewingStats.totalSessions)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Section("Akcje") {
                Button("Wyczyść statystyki") { analyticsService.clearStatistics() }
                    .help("Usuń wszystkie dane statystyk oglądania")
                Button("Eksportuj statystyki") { exportStatistics() }
                    .help("Eksportuj statystyki do pliku JSON")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAnalytics) {
            AnalyticsView(analyticsService: analyticsService)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)min" : "\(minutes)min"
    }

    private func exportStatistics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "aether-statistics.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let data = analyticsService.exportStatistics() {
                try? data.write(to: url)
            }
        }
    }

    // MARK: - Advanced Tab

    @State private var crashReportingService = CrashReportingService()
    @State private var memoryMonitor = MemoryMonitorService()
    @State private var showCrashReports = false
    @State private var showMemoryMonitor = false

    private var advancedTab: some View {
        Form {
            Section("Historia oglądania") {
                Button("Zresetuj historię oglądania", role: .destructive) {
                    showResetHistoryConfirm = true
                }
                .help("Usuwa całą historię oglądania ze SwiftData.")
                .confirmationDialog(
                    "Zresetować historię?",
                    isPresented: $showResetHistoryConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Resetuj historię", role: .destructive) { resetWatchHistory() }
                    Button("Anuluj", role: .cancel) {}
                } message: {
                    Text("Tej operacji nie można cofnąć.")
                }
            }

            Section("Cache") {
                Button("Wyczyść wszystkie cache") { clearAllCaches() }
                    .help("Czyści cache EPG, logo i pliki tymczasowe.")
            }

            Section("Raportowanie błędów") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Raporty awaryjne")
                            .font(.body)
                        Text("\(crashReportingService.crashReports.count) raportów")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Pokaż raporty") { showCrashReports = true }
                        .buttonStyle(.bordered)
                }
            }

            Section("Pamięć") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Status pamięci")
                            .font(.body)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(memoryPressureColor)
                                .frame(width: 8, height: 8)
                            Text(memoryMonitor.memoryPressure.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Szczegóły") { showMemoryMonitor = true }
                        .buttonStyle(.bordered)
                }
            }

            Section("Debug") {
                Toggle("Włącz logowanie debug", isOn: .constant(false))
                    .help("Włącz szczegółowe logi do diagnostyki.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showCrashReports) {
            CrashReportsView(service: crashReportingService)
        }
        .sheet(isPresented: $showMemoryMonitor) {
            MemoryMonitorView(memoryMonitor: memoryMonitor)
        }
    }

    private var memoryPressureColor: Color {
        switch memoryMonitor.memoryPressure {
        case .normal:   return .green
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    private func resetWatchHistory() {
        let descriptor = FetchDescriptor<WatchHistoryRecord>()
        guard let records = try? modelContext.fetch(descriptor) else { return }
        for record in records { modelContext.delete(record) }
        try? modelContext.save()
    }

    private func clearAllCaches() {
        Task {
            await epgStore.clearCache()
            URLCache.shared.removeAllCachedResponses()
            refreshCacheSize()
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        Form {
            Section("Informacje o aplikacji") {
                LabeledContent("Wersja", value: appVersion)
                LabeledContent("Build", value: buildNumber)
                LabeledContent("Platforma", value: "macOS 14+")
            }
            Section("Linki") {
                Button("GitHub — zgłoś problem") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/desireeformore-afk/aether/issues")!)
                }
                Button("Strona projektu") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/desireeformore-afk/aether")!)
                }
            }
            Section {
                Text("Copyright © 2025 Aether. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Helpers

    private var logosCacheDescription: String {
        let mb = Double(URLCache.shared.currentDiskUsage) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private func refreshCacheSize() {
        cacheSize = Self.epgCacheSizeString()
    }

    private static func epgCacheSizeString() -> String {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return "Nieznany"
        }
        let dir = appSupport
            .appendingPathComponent("Aether")
            .appendingPathComponent("EPGCache")
        guard fm.fileExists(atPath: dir.path) else { return "Pusty" }

        var bytes: Int64 = 0
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            for fileURL in files {
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                bytes += Int64(size)
            }
        }
        guard bytes > 0 else { return "Pusty" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    // MARK: - Playlist Import/Export

    private func showExportMessage(_ msg: String) {
        exportMessage = msg
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if exportMessage == msg { exportMessage = nil }
        }
    }

    private func showImportMessage(_ msg: String) {
        importMessage = msg
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if importMessage == msg { importMessage = nil }
        }
    }

    private func exportPlaylist() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!]
        panel.nameFieldStringValue = "playlist.m3u"
        panel.message = "Eksportuj playlistę do pliku M3U"

        let snapshotPlaylists = playlists
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    var allChannels: [Channel] = []
                    for playlist in snapshotPlaylists {
                        let channels = await ChannelCache.shared.load(playlistID: playlist.id)
                        allChannels.append(contentsOf: channels)
                    }
                    try await PlaylistExporter.export(to: url, channels: allChannels)
                    showExportMessage("✓ Playlista wyeksportowana pomyślnie")
                } catch {
                    showExportMessage("Błąd: \(error.localizedDescription)")
                }
            }
        }
    }

    private func importPlaylist() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!]
        panel.message = "Wybierz plik M3U do importu"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let name = url.deletingPathExtension().lastPathComponent
            Task { @MainActor in
                do {
                    let count = try await PlaylistImporter.import(from: url, name: name, modelContext: modelContext)
                    showImportMessage("✓ Zaimportowano \(count) kanałów pomyślnie")
                } catch {
                    showImportMessage("Błąd: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - AccountPlaylistRow

private struct AccountPlaylistRow: View {
    let playlist: PlaylistRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: playlist.playlistType == .xtream ? "server.rack" : "play.rectangle.on.rectangle")
                .font(.system(size: 18))
                .foregroundStyle(Color.aetherPrimary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(playlist.playlistType == .xtream ? "Xtream Codes" : "M3U")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let host = playlist.xstreamHost ?? (playlist.url?.host()) {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let refreshed = playlist.lastRefreshed {
                Text(refreshed, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Stream Quality

/// Available stream quality presets (stored in UserDefaults as rawValue).
enum StreamQuality: String, CaseIterable, Sendable {
    case auto   = "auto"
    case high   = "high"
    case medium = "medium"
    case low    = "low"

    var displayName: String {
        switch self {
        case .auto:   return "Auto (najlepsza dostępna)"
        case .high:   return "Wysoka"
        case .medium: return "Średnia"
        case .low:    return "Niska (oszczędność danych)"
        }
    }
}
