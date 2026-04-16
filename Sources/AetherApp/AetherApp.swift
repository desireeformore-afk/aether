import SwiftUI
import SwiftData
import AetherCore

@main
struct AetherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [PlaylistRecord.self, ChannelRecord.self])
    }
}
