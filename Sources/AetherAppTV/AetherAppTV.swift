import SwiftUI
import SwiftData
import AetherCore

#if os(tvOS)
@main
struct AetherAppTV: App {
    @StateObject private var playerCore = PlayerCore()
    @StateObject private var epgStore = EPGStore()

    var body: some Scene {
        WindowGroup {
            TVContentView(playerCore: playerCore)
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
