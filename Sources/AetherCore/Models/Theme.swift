import SwiftUI

// MARK: - ThemeBackground

/// Defines the visual background style for a theme.
public enum ThemeBackground: Sendable {
    /// Solid colour, represented as a hex string (e.g. "#1C1C1E").
    case solid(color: String)
    /// Linear gradient from an ordered list of hex colours.
    case gradient(colors: [String], startPoint: String, endPoint: String)
}

// MARK: - ThemeDefinition

/// A named visual theme for the Aether UI.
public struct ThemeDefinition: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Accent colour as a hex string.
    public let accentHex: String
    public let background: ThemeBackground
    /// Surface/card colour as a hex string.
    public let surfaceHex: String
    /// Primary text colour as a hex string.
    public let textHex: String

    public init(
        id: String,
        name: String,
        accentHex: String,
        background: ThemeBackground,
        surfaceHex: String,
        textHex: String
    ) {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.background = background
        self.surfaceHex = surfaceHex
        self.textHex = textHex
    }

    // MARK: - Built-in themes

    public static let allBuiltIn: [ThemeDefinition] = [
        ThemeDefinition(
            id: "default", name: "Aether",
            accentHex: "#5E5CE6",
            background: .solid(color: "#1C1C1E"),
            surfaceHex: "#2C2C2E", textHex: "#FFFFFF"
        ),
        ThemeDefinition(
            id: "amoled", name: "AMOLED",
            accentHex: "#00FFCC",
            background: .solid(color: "#000000"),
            surfaceHex: "#111111", textHex: "#FFFFFF"
        ),
        ThemeDefinition(
            id: "nord", name: "Nord",
            accentHex: "#88C0D0",
            background: .solid(color: "#2E3440"),
            surfaceHex: "#3B4252", textHex: "#ECEFF4"
        ),
        ThemeDefinition(
            id: "catppuccin", name: "Catppuccin",
            accentHex: "#CBA6F7",
            background: .solid(color: "#1E1E2E"),
            surfaceHex: "#313244", textHex: "#CDD6F4"
        ),
        ThemeDefinition(
            id: "sunset", name: "Sunset",
            accentHex: "#FF6B6B",
            background: .gradient(
                colors: ["#1a1a2e", "#16213e", "#0f3460"],
                startPoint: "top", endPoint: "bottom"
            ),
            surfaceHex: "#1a1a2e", textHex: "#FFFFFF"
        ),
    ]
}

// MARK: - SwiftUI Helpers

extension ThemeDefinition {
    /// Converts `accentHex` to a SwiftUI Color.
    public var accentColor: Color { Color(hex: accentHex) }
    /// Converts `surfaceHex` to a SwiftUI Color.
    public var surfaceColor: Color { Color(hex: surfaceHex) }
    /// Converts `textHex` to a SwiftUI Color.
    public var textColor: Color { Color(hex: textHex) }

    /// Returns a `View` that renders the background (solid or gradient).
    @ViewBuilder
    public func backgroundView() -> some View {
        switch background {
        case .solid(let hex):
            Color(hex: hex)
        case .gradient(let hexes, let start, let end):
            LinearGradient(
                colors: hexes.map { Color(hex: $0) },
                startPoint: unitPoint(from: start),
                endPoint: unitPoint(from: end)
            )
        }
    }

    private func unitPoint(from string: String) -> UnitPoint {
        switch string {
        case "top":       return .top
        case "bottom":    return .bottom
        case "leading":   return .leading
        case "trailing":  return .trailing
        case "topLeading":    return .topLeading
        case "topTrailing":   return .topTrailing
        case "bottomLeading": return .bottomLeading
        default:          return .bottom
        }
    }
}

// MARK: - Color(hex:) helper

extension Color {
    /// Creates a Color from a hex string like "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
