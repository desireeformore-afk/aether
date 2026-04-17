import Foundation
import AetherCore

/// Manages the active UI theme and persists selection to UserDefaults.
@MainActor
public final class ThemeService: ObservableObject {
    @Published public private(set) var active: ThemeDefinition

    private let defaults: UserDefaults
    private let key = "selectedThemeID"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "selectedThemeID") ?? "default"
        self.active = ThemeDefinition.allBuiltIn.first { $0.id == saved }
            ?? ThemeDefinition.allBuiltIn[0]
    }

    /// Selects a theme and persists the choice.
    public func select(_ theme: ThemeDefinition) {
        active = theme
        defaults.set(theme.id, forKey: key)
    }
}
