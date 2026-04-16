import SwiftUI
import SwiftData
import AetherCore

@main
struct AetherApp: App {
    @StateObject private var epgStore = EPGStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(epgStore)
        }
        .modelContainer(for: [PlaylistRecord.self, ChannelRecord.self, FavoriteRecord.self])

        Settings {
            SettingsView()
                .environmentObject(epgStore)
        }
    }
}
