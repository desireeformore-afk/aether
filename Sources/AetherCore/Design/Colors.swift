import SwiftUI

public extension Color {
    static let aetherBackground = Color(nsColor: .windowBackgroundColor)
    static let aetherSurface = Color(nsColor: .controlBackgroundColor)
    static let aetherAccent = Color.accentColor
    static let aetherPrimary = Color(nsColor: .labelColor)
    static let aetherSecondary = Color(nsColor: .secondaryLabelColor)
    static let aetherDestructive = Color(nsColor: .systemRed)
    static let aetherText = Color(nsColor: .labelColor)

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
