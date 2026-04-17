import SwiftUI

public extension Color {
    #if os(macOS)
    static let aetherBackground = Color(nsColor: .windowBackgroundColor)
    static let aetherSurface    = Color(nsColor: .controlBackgroundColor)
    static let aetherPrimary    = Color(nsColor: .labelColor)
    static let aetherSecondary  = Color(nsColor: .secondaryLabelColor)
    static let aetherDestructive = Color(nsColor: .systemRed)
    static let aetherText       = Color(nsColor: .labelColor)
    #else
    static let aetherBackground = Color(uiColor: .systemBackground)
    static let aetherSurface    = Color(uiColor: .secondarySystemBackground)
    static let aetherPrimary    = Color(uiColor: .label)
    static let aetherSecondary  = Color(uiColor: .secondaryLabel)
    static let aetherDestructive = Color(uiColor: .systemRed)
    static let aetherText       = Color(uiColor: .label)
    #endif

    static let aetherAccent = Color.accentColor

    /// Initialises a `Color` from a CSS hex string like `"#RRGGBB"`.
    /// Returns `nil` if the string is not a valid 6-digit hex value.
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
