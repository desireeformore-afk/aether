import SwiftUI
import SwiftData
import AetherCore
import AetherUI

#if os(iOS)
@main
struct AetherAppIOS: App {
    @StateObject private var playerCore = PlayerCore()
    @StateObject private var epgStore = EPGStore()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            IOSContentView(playerCore: playerCore)
                .environmentObject(epgStore)
                .environmentObject(playerCore)
                .sheet(isPresented: .constant(!hasCompletedOnboarding)) {
                    OnboardingView(isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { hasCompletedOnboarding = !$0 }
                    ))
                    .interactiveDismissDisabled()
                }
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
