import SwiftUI
import AetherCore

// MARK: - BrandHub + SwiftUI presentation

/// SwiftUI-specific extensions on BrandHub. Core logic lives in AetherCore/Models/VODNormalizer.swift.
public extension BrandHub {

    var themeColor: Color {
        switch self {
        case .netflix: return Color(red: 0.89, green: 0.04, blue: 0.08)
        case .hbo:     return Color(red: 0.36, green: 0.15, blue: 0.77)
        case .apple:   return Color(white: 0.85)
        case .disney:  return Color(red: 0.01, green: 0.06, blue: 0.28)
        case .amazon:  return Color(red: 0.0,  green: 0.65, blue: 0.89)
        case .anime:   return Color(red: 0.96, green: 0.45, blue: 0.0)
        case .kids:    return Color(red: 0.2,  green: 0.8,  blue: 0.2)
        case .poland:  return Color.accentColor
        case .other:   return Color.gray.opacity(0.4)
        }
    }

    var systemImage: String {
        switch self {
        case .netflix: return "n.square.fill"
        case .hbo:     return "popcorn.fill"
        case .apple:   return "apple.logo"
        case .disney:  return "star.circle.fill"
        case .amazon:  return "a.square.fill"
        case .anime:   return "sparkles"
        case .kids:    return "figure.2.and.child.holdinghands"
        case .poland:  return "film.stack"
        case .other:   return "play.rectangle.fill"
        }
    }
}
