import SwiftUI
import SwiftData
import AetherCore
import AetherUI

#if os(tvOS)
@main
struct AetherAppTV: App {
    @StateObject private var playerCore = PlayerCore()
    @StateObject private var epgStore = EPGStore()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            TVContentView(playerCore: playerCore)
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
