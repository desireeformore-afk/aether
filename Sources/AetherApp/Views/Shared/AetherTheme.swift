import SwiftUI

enum AetherTheme {
    enum ColorToken {
        static let background = Color(.sRGB, red: 0.035, green: 0.036, blue: 0.042, opacity: 1)
        static let surface = Color(.sRGB, red: 0.075, green: 0.078, blue: 0.088, opacity: 1)
        static let elevated = Color(.sRGB, red: 0.105, green: 0.108, blue: 0.122, opacity: 1)
        static let primaryText = Color.white
        static let secondaryText = Color.white.opacity(0.68)
        static let tertiaryText = Color.white.opacity(0.42)
        static let accent = Color(.sRGB, red: 0.12, green: 0.48, blue: 1.0, opacity: 1)
        static let gold = Color(.sRGB, red: 0.86, green: 0.70, blue: 0.36, opacity: 1)
        static let hairline = Color.white.opacity(0.10)
    }

    enum Radius {
        static let card: CGFloat = 10
        static let sheet: CGFloat = 16
        static let control: CGFloat = 9
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 40
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
        static let standard = Animation.easeInOut(duration: 0.24)
        static let spring = Animation.spring(response: 0.32, dampingFraction: 0.76)
    }
}
