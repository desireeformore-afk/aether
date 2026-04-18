import SwiftUI
import SwiftData
import AetherCore
import AetherUI

#if os(iOS)
// @main is defined in the Xcode scheme entry point, not in SPM library target
struct AetherAppIOS: App {
    @StateObject private var playerCore = PlayerCore()
    @StateObject private var epgStore = EPGStore()
    @StateObject private var themeService = ThemeService()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            IOSContentView(playerCore: playerCore)
                .environmentObject(epgStore)
                .environmentObject(playerCore)
                .environmentObject(themeService)
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
            FavoriteRecord.self,
            WatchHistoryRecord.self,
        ])
    }
}
#endif
