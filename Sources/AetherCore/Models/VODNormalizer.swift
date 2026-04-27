import Foundation

// MARK: - BrandHub

/// Identifies a streaming platform hub. SwiftUI presentation extensions live in AetherApp.
public enum BrandHub: String, CaseIterable, Identifiable, Hashable, Sendable {
    case netflix  = "Netflix"
    case hbo      = "Max"
    case apple    = "Apple TV+"
    case disney   = "Disney+"
    case amazon   = "Prime Video"
    case anime    = "Anime"
    case kids     = "Kids"
    case poland   = "Movies"
    case other    = "Other"

    public var id: String { rawValue }
}

// MARK: - VODTag

public enum VODTag: String, Hashable, Identifiable, Sendable {
    case uhd4k = "4K"
    case fhd   = "1080p"
    case hd    = "720p"
    case hdr   = "HDR"
    case langPL = "PL"
    case dubPL  = "PL DUB"
    case subPL  = "PL SUB"
    case langEN = "EN"
    case subEN  = "EN SUB"
    case langDE = "DE"
    case langFR = "FR"
    case langIT = "IT"
    case langES = "ES"
    case langTR = "TR"
    case langRU = "RU"

    public var id: String { rawValue }

    public var isResolution: Bool {
        self == .uhd4k || self == .fhd || self == .hd || self == .hdr
    }

    public var isLanguage: Bool { !isResolution }
}

// MARK: - VODNormalizer

public struct VODNormalizer {

    // MARK: Hub mapping

    /// Maps a raw IPTV category name to a normalized premium BrandHub.
    public static func mapCategoryToHub(categoryName: String) -> BrandHub {
        CategoryNormalizer.hub(for: categoryName)
    }

    // MARK: Shelf name

    /// Maps a raw category name + hub to a clean English genre shelf label.
    public static func normalizeShelfName(categoryName: String, hub: BrandHub) -> String {
        let normalizedCategory = CategoryNormalizer.normalize(
            rawName: categoryName,
            provider: .unknown,
            contentType: .movie
        )
        let name = "\(categoryName) \(normalizedCategory.displayName)".lowercased()
        let isKids   = name.contains("kids") || name.contains("dzieci") || name.contains("bajki") || name.contains("family") || name.contains("animacj")
        let isDoc    = name.contains("docu") || name.contains("dokument")
        let isAction = name.contains("akcj") || name.contains("action")
        let isComedy = name.contains("komedi") || name.contains("comedy")
        let isDrama  = name.contains("dramat") || name.contains("drama")
        let isHorror = name.contains("horror") || name.contains("thriller") || name.contains("grozy")
        let isSciFi  = name.contains("scifi") || name.contains("sci-fi") || name.contains("fantasy") || name.contains("s-f")
        let genre: String? = {
            if isKids   { return "Family & Kids" }
            if isDoc    { return "Documentaries" }
            if isAction { return "Action" }
            if isComedy { return "Comedy" }
            if isHorror { return "Horror & Thriller" }
            if isSciFi  { return "Sci-Fi & Fantasy" }
            if isDrama  { return "Drama" }
            return nil
        }()
        switch hub {
        case .apple, .netflix, .amazon, .disney, .hbo: return genre ?? "Featured"
        case .anime:   return "World Anime"
        case .kids:    return "Kids & Family"
        case .poland:  return genre ?? "Classic Movies"
        case .other:   return genre ?? "Miscellaneous"
        }
    }

    // MARK: Title cleaning — precompiled regex (CPU saver)

    private static let providerPrefixRegex = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9\s\|\-\[\]]+(?:netflix|amz|nf|hbo|max|atvp|dsnp|prime|apple|4k|fhd|hd|pl|anime)[\s\|\-]+"#,
        options: .caseInsensitive
    )
    private static let endTagsRegex = try! NSRegularExpression(
        pattern: #"(?:\s*[\[\(\{][^\]\)\}]+[\]\)\}])+\s*$"#,
        options: .caseInsensitive
    )
    private static let looseCodeRegex = try! NSRegularExpression(
        pattern: #"^(?:PL|EN|DE|FR|IT|ES|TR|RU)\s*(?:-|\|)\s*"#,
        options: .caseInsensitive
    )

    private static let directPrefixes: [String] = [
        "4K-A+ - ", "4K-A+ ", "4k-a+ - ", "4k-a+ ",
        "4K-D+ - ", "4K-D+ ", "4K-N+ - ", "4K-N+ ", "4K-H+ - ", "4K-H+ ", "4K-M+ - ", "4K-M+ ",
        "A+ - ", "A+-", "A+ ", "a+ - ", "a+-", "a+ ",
        "D+ - ", "D+-", "D+ ", "N+ - ", "N+-", "N+ ", "H+ - ", "H+-", "H+ ", "M+ - ", "M+-", "M+ ",
        "AMZ - ", "AMZ-", "NF - ", "NF-", "NETFLIX - ", "Netflix - ", "APPLE+ - ", "Disney+ - ", "MAX - ", "HBO - ",
        "DSNP - ", "ATVP - ", "PL - ", "PL|", "EN - ", "EN|", "DE - ", "DE|",
        "FR - ", "FR|", "IT - ", "IT|", "ES - ", "ES|", "TR - ", "TR|", "RU - ", "RU|",
        "DE ", "EN ", "PL ", "FR ", "IT ", "ES ", "TR ", "RU "
    ]

    /// Returns a cleaned title with provider prefixes and quality tags stripped.
    public static func cleanVODTitle(_ original: String) -> String {
        var s = original
        func range() -> NSRange { NSRange(location: 0, length: s.utf16.count) }
        s = providerPrefixRegex.stringByReplacingMatches(in: s, range: range(), withTemplate: "")
        s = endTagsRegex.stringByReplacingMatches(in: s, range: range(), withTemplate: "")
        s = s.replacingOccurrences(of: " [4K]", with: "")
        s = s.replacingOccurrences(of: " (HD)", with: "")
        s = s.replacingOccurrences(of: " [PL DUB]", with: "")
        s = looseCodeRegex.stringByReplacingMatches(in: s, range: range(), withTemplate: "")
        for p in directPrefixes {
            if s.uppercased().hasPrefix(p.uppercased()) {
                s = String(s.dropFirst(p.count))
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Tag extraction

    /// Extracts quality/language tags and returns a cleaned title + tag set.
    public static func extractTagsAndClean(_ original: String) -> (cleanTitle: String, tags: Set<VODTag>) {
        var tags = Set<VODTag>()
        let upper = original.uppercased()

        if upper.contains("4K") || upper.contains("UHD")          { tags.insert(.uhd4k) }
        else if upper.contains("1080") || upper.contains("FHD")    { tags.insert(.fhd) }
        else if upper.contains("[HD]") || upper.contains(" 720")   { tags.insert(.hd) }
        if upper.contains("HDR") { tags.insert(.hdr) }

        if upper.contains("PL DUB") || upper.contains("DUB PL") || upper.contains("LEKTOR PL") { tags.insert(.dubPL) }
        else if upper.contains("PL SUB") || upper.contains("SUB PL") || upper.contains("NAPISY") { tags.insert(.subPL) }
        else if upper.contains("[PL]") || upper.contains("(PL)") || upper.hasPrefix("PL ") || upper.hasSuffix(" PL") || upper.contains("PL|") || upper.contains("PL-") { tags.insert(.langPL) }

        if upper.contains("EN SUB") || upper.contains("SUB EN") { tags.insert(.subEN) }
        else if upper.contains("[EN]") || upper.contains("(EN)") || upper.hasPrefix("EN ") || upper.hasSuffix(" EN") || upper.contains("ENGLISH") || upper.contains("EN|") || upper.contains("EN-") { tags.insert(.langEN) }

        if upper.contains("[DE]") || upper.contains("(DE)") || upper.hasPrefix("DE ") || upper.hasSuffix(" DE") || upper.contains("DE|") || upper.contains("DE-") { tags.insert(.langDE) }
        if upper.contains("[FR]") || upper.contains("(FR)") || upper.hasPrefix("FR ") || upper.hasSuffix(" FR") || upper.contains("FR|") || upper.contains("FR-") { tags.insert(.langFR) }
        if upper.contains("[IT]") || upper.contains("(IT)") || upper.hasPrefix("IT ") || upper.hasSuffix(" IT") || upper.contains("IT|") || upper.contains("IT-") { tags.insert(.langIT) }
        if upper.contains("[ES]") || upper.contains("(ES)") || upper.hasPrefix("ES ") || upper.hasSuffix(" ES") || upper.contains("ES|") || upper.contains("ES-") { tags.insert(.langES) }
        if upper.contains("[TR]") || upper.contains("(TR)") || upper.hasPrefix("TR ") || upper.hasSuffix(" TR") || upper.contains("TR|") || upper.contains("TR-") { tags.insert(.langTR) }
        if upper.contains("[RU]") || upper.contains("(RU)") || upper.hasPrefix("RU ") || upper.hasSuffix(" RU") || upper.contains("RU|") || upper.contains("RU-") { tags.insert(.langRU) }

        return (cleanVODTitle(original), tags)
    }
}
