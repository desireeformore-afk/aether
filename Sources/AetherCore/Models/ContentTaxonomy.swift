import Foundation

/// Provider family for raw category metadata.
public enum ContentCategoryProvider: String, Codable, Sendable, Hashable {
    case m3u
    case xtream
    case unknown
}

/// Presentation role assigned to a provider category after normalization.
public enum ContentCategoryRole: String, Codable, Sendable, Hashable {
    case platform
    case genre
    case language
    case quality
    case adult
    case providerFallback
    case providerNoise
    case hidden
}

/// Why a category was hidden from, or demoted within, primary presentation.
public enum ContentCategoryNoiseReason: String, Codable, Sendable, Hashable {
    case empty
    case adult
    case vip
    case premium
    case backup
    case test
    case qualityOnly
    case languageOnly
    case arabicScript
    case numericOnly
    case providerNoise
}

/// Raw provider category reference. Keep this around so UI/catalog code can show
/// a cleaned name without losing provider metadata.
public struct RawProviderCategory: Codable, Sendable, Hashable {
    public let provider: ContentCategoryProvider
    public let contentType: ContentType
    public let rawID: String?
    public let rawName: String?

    public init(
        provider: ContentCategoryProvider,
        contentType: ContentType,
        rawID: String? = nil,
        rawName: String? = nil
    ) {
        self.provider = provider
        self.contentType = contentType
        self.rawID = rawID
        self.rawName = rawName
    }
}

/// Normalized category metadata used for browsing/search presentation.
///
/// Lower `priority` values should be shown earlier. `isPrimaryVisible == false`
/// means the content should remain available, but the category should not drive
/// top-level shelves/chips.
public struct NormalizedContentCategory: Codable, Sendable, Hashable, Identifiable {
    public let raw: RawProviderCategory
    public let displayName: String
    public let stableKey: String
    public let role: ContentCategoryRole
    public let priority: Int
    public let isPrimaryVisible: Bool
    public let noiseReasons: [ContentCategoryNoiseReason]

    public var id: String { stableKey }

    public init(
        raw: RawProviderCategory,
        displayName: String,
        stableKey: String,
        role: ContentCategoryRole,
        priority: Int,
        isPrimaryVisible: Bool,
        noiseReasons: [ContentCategoryNoiseReason] = []
    ) {
        self.raw = raw
        self.displayName = displayName
        self.stableKey = stableKey
        self.role = role
        self.priority = priority
        self.isPrimaryVisible = isPrimaryVisible
        self.noiseReasons = noiseReasons
    }
}
