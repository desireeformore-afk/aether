import SwiftUI
import SwiftData
import AetherCore

#if os(iOS)
@main
struct AetherAppIOS: App {
    @StateObject private var playerCore = PlayerCore()
    @StateObject private var epgStore = EPGStore()

    var body: some Scene {
        WindowGroup {
            IOSContentView(playerCore: playerCore)
                .environmentObject(epgStore)
                .environmentObject(playerCore)
        }
        .modelContainer(for: [
            PlaylistRecord.self,
            ChannelRecord.self,
            FavoriteRecord.self,
            WatchHistoryRecord.self,
        ])
    }
}
#endif
