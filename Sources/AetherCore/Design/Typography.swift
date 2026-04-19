#if canImport(SwiftUI)
import SwiftUI

public extension Font {
    static let aetherTitle: Font = .system(.title, design: .rounded, weight: .semibold)
    static let aetherHeadline: Font = .system(.headline, design: .rounded, weight: .medium)
    static let aetherBody: Font = .system(.body, design: .default, weight: .regular)
    static let aetherCaption: Font = .system(.caption, design: .default, weight: .regular)
    static let aetherMono: Font = .system(.body, design: .monospaced, weight: .regular)
}

#endif // canImport(SwiftUI)
