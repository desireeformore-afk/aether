import SwiftUI
import AetherCore

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

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

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
