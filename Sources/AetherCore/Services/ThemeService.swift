import Foundation
import Observation

/// Manages the active UI theme and persists selection to UserDefaults.
@MainActor
@Observable
public final class ThemeService {
    public private(set) var active: ThemeDefinition

    private let defaults: UserDefaults
    private let selectedKey = "selectedThemeID"
    private let customGradientKey = "customGradientTheme"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Try loading custom gradient first (if it was the last selected)
        let savedID = defaults.string(forKey: "selectedThemeID") ?? "default"
        if savedID == "custom_gradient",
           let data = defaults.data(forKey: "customGradientTheme"),
           let custom = try? JSONDecoder().decode(PersistedCustomTheme.self, from: data) {
            self.active = custom.toThemeDefinition()
        } else {
            self.active = ThemeDefinition.allBuiltIn.first { $0.id == savedID }
                ?? ThemeDefinition.allBuiltIn[0]
        }
    }

    /// Selects a built-in theme and persists the choice.
    public func select(_ theme: ThemeDefinition) {
        active = theme
        defaults.set(theme.id, forKey: selectedKey)

        // If custom gradient, persist its full definition
        if theme.id == "custom_gradient" {
            if let persisted = PersistedCustomTheme(from: theme),
               let data = try? JSONEncoder().encode(persisted) {
                defaults.set(data, forKey: customGradientKey)
            }
        }
    }

    /// All available themes: built-ins + custom gradient (if saved).
    public var allThemes: [ThemeDefinition] {
        var themes = ThemeDefinition.allBuiltIn
        if let data = defaults.data(forKey: customGradientKey),
           let custom = try? JSONDecoder().decode(PersistedCustomTheme.self, from: data) {
            themes.append(custom.toThemeDefinition())
        }
        return themes
    }
}

// MARK: - Codable bridge for custom gradient persistence

private struct PersistedCustomTheme: Codable {
    let id: String
    let name: String
    let accentHex: String
    let surfaceHex: String
    let textHex: String
    // gradient fields
    let gradientColors: [String]
    let startPoint: String
    let endPoint: String

    init?(from theme: ThemeDefinition) {
        guard case .gradient(let colors, let start, let end) = theme.background else { return nil }
        self.id = theme.id
        self.name = theme.name
        self.accentHex = theme.accentHex
        self.surfaceHex = theme.surfaceHex
        self.textHex = theme.textHex
        self.gradientColors = colors
        self.startPoint = start
        self.endPoint = end
    }

    func toThemeDefinition() -> ThemeDefinition {
        ThemeDefinition(
            id: id,
            name: name,
            accentHex: accentHex,
            background: .gradient(colors: gradientColors, startPoint: startPoint, endPoint: endPoint),
            surfaceHex: surfaceHex,
            textHex: textHex
        )
    }
}
