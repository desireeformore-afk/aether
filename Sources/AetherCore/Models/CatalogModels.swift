import Foundation

public enum CatalogMediaKind: String, Codable, Sendable, Hashable {
    case movie
    case series
    case live
}

public enum CatalogSectionRole: String, Codable, Sendable, Hashable {
    case continueWatching
    case recommended
    case topRated
    case ultraHD
    case movies
    case series
    case platformHub
    case genre
}

public struct MediaVariant: Identifiable, Hashable, Sendable {
    public let id: String
    public let providerID: Int
    public let title: String
    public let cleanTitle: String
    public let languageLabel: String?
    public let qualityLabel: String?
    public let container: String?
    public let tags: Set<VODTag>
    public let vod: XstreamVOD?

    public var displayLabel: String {
        var parts: [String] = []
        if let languageLabel { parts.append(languageLabel) }
        if let qualityLabel { parts.append(qualityLabel) }
        if let container, !container.isEmpty { parts.append(container.uppercased()) }
        return parts.isEmpty ? title : parts.joined(separator: " | ")
    }

    public init(
        id: String,
        providerID: Int,
        title: String,
        cleanTitle: String,
        languageLabel: String?,
        qualityLabel: String?,
        container: String?,
        tags: Set<VODTag>,
        vod: XstreamVOD?
    ) {
        self.id = id
        self.providerID = providerID
        self.title = title
        self.cleanTitle = cleanTitle
        self.languageLabel = languageLabel
        self.qualityLabel = qualityLabel
        self.container = container
        self.tags = tags
        self.vod = vod
    }
}

public struct UnifiedMediaItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: CatalogMediaKind
    public let title: String
    public let posterURLString: String?
    public let rating: String?
    public let year: String?
    public let genre: String?
    public let categoryName: String?
    public let normalizedCategory: NormalizedContentCategory?
    public let brandHub: BrandHub?
    public let tags: Set<VODTag>
    public let variants: [MediaVariant]
    public let series: XstreamSeries?

    public var primaryVariant: MediaVariant? { variants.first }
    public var primaryVOD: XstreamVOD? { primaryVariant?.vod }
    public var vodVariants: [XstreamVOD] { variants.compactMap(\.vod) }

    public init(
        id: String,
        kind: CatalogMediaKind,
        title: String,
        posterURLString: String?,
        rating: String?,
        year: String?,
        genre: String?,
        categoryName: String?,
        normalizedCategory: NormalizedContentCategory?,
        brandHub: BrandHub?,
        tags: Set<VODTag>,
        variants: [MediaVariant],
        series: XstreamSeries?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.posterURLString = posterURLString
        self.rating = rating
        self.year = year
        self.genre = genre
        self.categoryName = categoryName
        self.normalizedCategory = normalizedCategory
        self.brandHub = brandHub
        self.tags = tags
        self.variants = variants
        self.series = series
    }
}

public struct CatalogSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let role: CatalogSectionRole
    public let kind: CatalogMediaKind
    public let hub: BrandHub?
    public let items: [UnifiedMediaItem]

    public init(
        id: String,
        title: String,
        role: CatalogSectionRole,
        kind: CatalogMediaKind,
        hub: BrandHub? = nil,
        items: [UnifiedMediaItem]
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.kind = kind
        self.hub = hub
        self.items = items
    }
}

public struct CatalogHubSection: Identifiable, Hashable, Sendable {
    public let hub: BrandHub
    public let sections: [CatalogSection]

    public var id: String { hub.id }

    public init(hub: BrandHub, sections: [CatalogSection]) {
        self.hub = hub
        self.sections = sections
    }
}

public struct CatalogSnapshot: Sendable {
    public static let empty = CatalogSnapshot(
        vodItems: [],
        seriesItems: [],
        movieSections: [],
        seriesSections: [],
        movieGenreSections: [],
        seriesGenreSections: [],
        brandHubSections: [],
        movieGenres: [],
        seriesGenres: []
    )

    public let vodItems: [UnifiedMediaItem]
    public let seriesItems: [UnifiedMediaItem]
    public let movieSections: [CatalogSection]
    public let seriesSections: [CatalogSection]
    public let movieGenreSections: [CatalogSection]
    public let seriesGenreSections: [CatalogSection]
    public let brandHubSections: [CatalogHubSection]
    public let movieGenres: [String]
    public let seriesGenres: [String]

    public var isEmpty: Bool { vodItems.isEmpty && seriesItems.isEmpty }

    public init(
        vodItems: [UnifiedMediaItem],
        seriesItems: [UnifiedMediaItem],
        movieSections: [CatalogSection],
        seriesSections: [CatalogSection],
        movieGenreSections: [CatalogSection],
        seriesGenreSections: [CatalogSection],
        brandHubSections: [CatalogHubSection],
        movieGenres: [String],
        seriesGenres: [String]
    ) {
        self.vodItems = vodItems
        self.seriesItems = seriesItems
        self.movieSections = movieSections
        self.seriesSections = seriesSections
        self.movieGenreSections = movieGenreSections
        self.seriesGenreSections = seriesGenreSections
        self.brandHubSections = brandHubSections
        self.movieGenres = movieGenres
        self.seriesGenres = seriesGenres
    }

    public func movieItems(inGenre genre: String) -> [UnifiedMediaItem] {
        movieGenreSections.first { $0.title == genre }?.items ?? []
    }

    public func seriesItems(inGenre genre: String) -> [UnifiedMediaItem] {
        seriesGenreSections.first { $0.title == genre }?.items ?? []
    }
}

public struct CatalogSearchResults: Sendable {
    public let movies: [UnifiedMediaItem]
    public let series: [UnifiedMediaItem]

    public init(movies: [UnifiedMediaItem], series: [UnifiedMediaItem]) {
        self.movies = movies
        self.series = series
    }
}

public enum CatalogVariantSelector {
    public static func preferredVOD(from vods: [XstreamVOD]) -> XstreamVOD? {
        sortedVODs(vods).first
    }

    public static func sortedVODs(_ vods: [XstreamVOD]) -> [XstreamVOD] {
        vods.sorted { lhs, rhs in
            let left = variantRank(for: lhs)
            let right = variantRank(for: rhs)
            if left != right { return isRank(left, orderedBefore: right) }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    public static func variantLabel(for vod: XstreamVOD) -> String {
        let (_, tags) = VODNormalizer.extractTagsAndClean(vod.name)
        let language = languageLabel(from: tags, title: vod.name) ?? "Auto"
        let quality = qualityLabel(from: tags, title: vod.name) ?? "Best"
        let container = (vod.containerExtension ?? "mp4").uppercased()
        return "\(language) | \(quality) | \(container)"
    }

    public static func variantRank(for vod: XstreamVOD) -> [Int] {
        let (_, tags) = VODNormalizer.extractTagsAndClean(vod.name)
        return [
            languageRank(tags: tags, title: vod.name),
            qualityRank(tags: tags, title: vod.name),
            containerRank(vod.containerExtension)
        ]
    }

    static func mediaVariant(for vod: XstreamVOD, cleanTitle: String, tags: Set<VODTag>) -> MediaVariant {
        MediaVariant(
            id: "vod-\(vod.id)",
            providerID: vod.id,
            title: vod.name,
            cleanTitle: cleanTitle,
            languageLabel: languageLabel(from: tags, title: vod.name),
            qualityLabel: qualityLabel(from: tags, title: vod.name),
            container: vod.containerExtension,
            tags: tags,
            vod: vod
        )
    }

    static func sortedVariants(_ variants: [MediaVariant]) -> [MediaVariant] {
        variants.sorted { lhs, rhs in
            let left = variantRank(tags: lhs.tags, title: lhs.title, container: lhs.container)
            let right = variantRank(tags: rhs.tags, title: rhs.title, container: rhs.container)
            if left != right { return isRank(left, orderedBefore: right) }
            return lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }

    static func variantRank(tags: Set<VODTag>, title: String, container: String?) -> [Int] {
        [
            languageRank(tags: tags, title: title),
            qualityRank(tags: tags, title: title),
            containerRank(container)
        ]
    }

    static func languageRank(tags: Set<VODTag>, title: String) -> Int {
        let upper = title.uppercased()
        if tags.contains(.dubPL) || upper.contains("LEKTOR PL") { return 0 }
        if tags.contains(.subPL) || upper.contains("NAPISY") { return 1 }
        if tags.contains(.langPL) { return 2 }
        if tags.contains(.langEN) { return 3 }
        if tags.contains(.subEN) { return 4 }
        return 5
    }

    static func qualityRank(tags: Set<VODTag>, title: String) -> Int {
        let upper = title.uppercased()
        if tags.contains(.uhd4k) || upper.contains("2160") { return 0 }
        if tags.contains(.hdr) { return 1 }
        if tags.contains(.fhd) || upper.contains("1080") { return 2 }
        if tags.contains(.hd) || upper.contains("720") { return 3 }
        return 4
    }

    static func containerRank(_ container: String?) -> Int {
        switch container?.lowercased() {
        case "m3u8": return 0
        case "mp4", "m4v": return 1
        case "mkv": return 2
        default: return 3
        }
    }

    private static func isRank(_ lhs: [Int], orderedBefore rhs: [Int]) -> Bool {
        for index in 0..<min(lhs.count, rhs.count) {
            if lhs[index] != rhs[index] { return lhs[index] < rhs[index] }
        }
        return lhs.count < rhs.count
    }

    static func languageLabel(from tags: Set<VODTag>, title: String) -> String? {
        let upper = title.uppercased()
        if tags.contains(.dubPL) || upper.contains("LEKTOR PL") { return "PL DUB" }
        if tags.contains(.subPL) || upper.contains("NAPISY") { return "PL SUB" }
        if tags.contains(.langPL) { return "PL" }
        if tags.contains(.langEN) { return "EN" }
        if tags.contains(.subEN) { return "EN SUB" }
        if tags.contains(.langDE) { return "DE" }
        if tags.contains(.langFR) { return "FR" }
        if tags.contains(.langIT) { return "IT" }
        if tags.contains(.langES) { return "ES" }
        if tags.contains(.langTR) { return "TR" }
        if tags.contains(.langRU) { return "RU" }
        return nil
    }

    static func qualityLabel(from tags: Set<VODTag>, title: String) -> String? {
        let upper = title.uppercased()
        if tags.contains(.uhd4k) || upper.contains("2160") { return "4K" }
        if tags.contains(.hdr) { return "HDR" }
        if tags.contains(.fhd) || upper.contains("1080") { return "1080p" }
        if tags.contains(.hd) || upper.contains("720") { return "720p" }
        return nil
    }
}
