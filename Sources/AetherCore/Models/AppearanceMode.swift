/// User preference for light / dark / system appearance.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    public var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
}

#if canImport(SwiftUI)
import SwiftUI

public extension AppearanceMode {
    /// The SwiftUI `ColorScheme` to apply, or `nil` for system default.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
#endif // canImport(SwiftUI)
