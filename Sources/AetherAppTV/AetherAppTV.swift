import SwiftUI
import SwiftData
import AetherCore
import AetherUI

#if os(tvOS)
// @main is defined in the Xcode scheme entry point, not in SPM library target
struct AetherAppTV: App {
    @State private var playerCore = PlayerCore()
    @State private var epgStore = EPGStore()
    @State private var themeService = ThemeService()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            TVContentView(playerCore: playerCore)
                .environment(epgStore)
                .environment(playerCore)
                .environment(themeService)
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
