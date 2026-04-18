import SwiftUI
import AetherCore
import AetherUI
import AppKit

/// App Settings panel — accessible via ⌘, / Aether > Settings…
struct SettingsView: View {
    @EnvironmentObject private var epgStore: EPGStore
    @EnvironmentObject private var themeService: ThemeService

    // MARK: - UserDefaults-backed preferences

    @AppStorage("epgRefreshInterval") private var epgRefreshInterval: Double = 3600
    @AppStorage("defaultStreamQuality") private var defaultStreamQuality: String = StreamQuality.auto.rawValue
    @AppStorage("useHardwareDecoding") private var useHardwareDecoding = true

    // MARK: - Local UI state

    @State private var showClearConfirm = false
    @State private var cacheSize: String = "Calculating…"
    @State private var showExportSheet = false
    @State private var showImportSheet = false
    @State private var exportMessage: String?
    @State private var importMessage: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            playlistTab
                .tabItem { Label("Playlists", systemImage: "list.bullet") }

            epgTab
                .tabItem { Label("EPG", systemImage: "calendar") }

            cacheTab
                .tabItem { Label("Cache", systemImage: "internaldrive") }

            SubtitleSettingsView()
                .tabItem { Label("Subtitles", systemImage: "captions.bubble") }
                .tag("subtitles")

            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag("appearance")

            parentalControlsTab
                .tabItem { Label("Parental Controls", systemImage: "lock.shield") }
                .tag("parental")
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { refreshCacheSize() }
    }

    // MARK: - Tabs

    private var generalTab: some View {
        Form {
            Section("Playback") {
                Picker("Default Quality", selection: $defaultStreamQuality) {
                    ForEach(StreamQuality.allCases, id: \.rawValue) { q in
                        Text(q.displayName).tag(q.rawValue)
                    }
                }

                Toggle("Use Hardware Decoding", isOn: $useHardwareDecoding)
                    .help("Enable Apple Silicon / GPU-accelerated video decoding.")
            }
        }
        .formStyle(.grouped)
    }

    private var playlistTab: some View {
        Form {
            Section("Import / Export") {
                Button("Export Playlist to M3U…") {
                    exportPlaylist()
                }
                .help("Export the current playlist to an M3U file.")

                Button("Import M3U File…") {
                    importPlaylist()
                }
                .help("Import channels from an M3U file.")
            }

            if let message = exportMessage {
                Section {
                    Text(message)
                        .foregroundStyle(message.contains("Error") ? .red : .green)
                        .font(.aetherCaption)
                }
            }

            if let message = importMessage {
                Section {
                    Text(message)
                        .foregroundStyle(message.contains("Error") ? .red : .green)
                        .font(.aetherCaption)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var epgTab: some View {
        Form {
            Section("Refresh") {
                Picker("EPG Refresh Interval", selection: $epgRefreshInterval) {
                    Text("Every 30 minutes").tag(1800.0)
                    Text("Every hour").tag(3600.0)
                    Text("Every 6 hours").tag(21600.0)
                    Text("Every 12 hours").tag(43200.0)
                    Text("Never").tag(0.0)
                }

                Toggle("Background Auto-Refresh", isOn: Binding(
                    get: { epgRefreshInterval > 0 },
                    set: { enabled in
                        if !enabled {
                            epgRefreshInterval = 0
                        } else if epgRefreshInterval == 0 {
                            epgRefreshInterval = 3600
                        }
                    }
                ))
                .help("Automatically refresh EPG data in the background.")

                Button("Refresh Now") {
                    Task { await epgStore.loadGuide(from: epgStore.currentEPGURL ?? URL(string: "about:blank")!, forceRefresh: true) }
                }
                .disabled(epgStore.currentEPGURL == nil)
                .help("Force a fresh EPG download from the current source.")
            }

            Section("Status") {
                LabeledContent("EPG Source") {
                    Text(epgStore.currentEPGURL?.host() ?? "None")
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
                    LabeledContent("Last Error") {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.aetherCaption)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var cacheTab: some View {
        Form {
            Section("Disk Usage") {
                LabeledContent("Cache Size", value: cacheSize)

                Button("Clear EPG Cache…", role: .destructive) {
                    showClearConfirm = true
                }
                .confirmationDialog(
                    "Clear EPG Cache?",
                    isPresented: $showClearConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Clear Cache", role: .destructive) {
                        Task {
                            await epgStore.clearCache()
                            refreshCacheSize()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes cached EPG data. EPG will be re-downloaded on next refresh.")
                }
            }

            Section("Logo Cache") {
                LabeledContent("Image Cache") {
                    Text(logosCacheDescription)
                        .foregroundStyle(.secondary)
                }
                Button("Clear Logo Cache") {
                    URLCache.shared.removeAllCachedResponses()
                    refreshCacheSize()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshCacheSize() }
    }

    // MARK: - Helpers

    private var logosCacheDescription: String {
        let mb = Double(URLCache.shared.currentDiskUsage) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private func refreshCacheSize() {
        // Run on a background thread without Task.detached to avoid
        // Swift 6 Sendable checks on FileManager.DirectoryEnumerator.
        let result = Self.epgCacheSizeString()
        cacheSize = result
    }

    /// Computes EPG cache size synchronously (call from MainActor is fine — fast FS op).
    private static func epgCacheSizeString() -> String {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return "Unknown"
        }
        let dir = appSupport
            .appendingPathComponent("Aether")
            .appendingPathComponent("EPGCache")
        guard fm.fileExists(atPath: dir.path) else { return "Empty" }

        var bytes: Int64 = 0
        // Use contentsOfDirectory to avoid non-Sendable enumerator in Swift 6
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            for fileURL in files {
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                bytes += Int64(size)
            }
        }
        guard bytes > 0 else { return "Empty" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AppearancePickerView()
                    .padding(.bottom, 4)

                Divider()

                ThemePickerView()
                    .environmentObject(themeService)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Parental Controls Tab

    @StateObject private var parentalService = ParentalControlService()

    private var parentalControlsTab: some View {
        ParentalControlsView(service: parentalService)
    }

    // MARK: - Playlist Import/Export

    private func exportPlaylist() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!]
        panel.nameFieldStringValue = "playlist.m3u"
        panel.message = "Export playlist to M3U file"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await PlaylistExporter.export(to: url)
                    exportMessage = "✓ Playlist exported successfully"
                } catch {
                    exportMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importPlaylist() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!]
        panel.message = "Select an M3U file to import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let count = try await PlaylistImporter.import(from: url)
                    importMessage = "✓ Imported \(count) channels successfully"
                } catch {
                    importMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Stream Quality

/// Available stream quality presets (stored in UserDefaults as rawValue).
enum StreamQuality: String, CaseIterable, Sendable {
    case auto = "auto"
    case high = "high"
    case medium = "medium"
    case low = "low"

    var displayName: String {
        switch self {
        case .auto:   return "Auto (Best Available)"
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low (Data Saver)"
        }
    }
}
