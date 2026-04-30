import Foundation

public actor CatalogIndex {
    private var signature = ""
    private var cachedSnapshot: CatalogSnapshot = .empty
    private var movieIndex: [IndexedCatalogItem] = []
    private var seriesIndex: [IndexedCatalogItem] = []

    public init() {}

    @discardableResult
    public func update(vods: [XstreamVOD], series: [XstreamSeries]) async -> CatalogSnapshot {
        let newSignature = Self.signature(vods: vods, series: series)
        guard newSignature != signature else { return cachedSnapshot }

        let snapshot = await Task.detached(priority: .utility) {
            CatalogBuilder.build(vods: vods, series: series)
        }.value

        signature = newSignature
        cachedSnapshot = snapshot
        movieIndex = snapshot.vodItems.map(IndexedCatalogItem.init(item:))
        seriesIndex = snapshot.seriesItems.map(IndexedCatalogItem.init(item:))
        return snapshot
    }

    public func snapshot() -> CatalogSnapshot {
        cachedSnapshot
    }

    public func hasIndexedContent() -> Bool {
        !movieIndex.isEmpty || !seriesIndex.isEmpty
    }

    public func search(query: String, limit: Int = 30) -> CatalogSearchResults {
        let normalizedQuery = SearchText.normalize(query)
        guard normalizedQuery.count >= 2, limit > 0 else {
            return CatalogSearchResults(movies: [], series: [])
        }

        return CatalogSearchResults(
            movies: Self.topMatches(movieIndex, query: normalizedQuery, limit: limit).map(\.item),
            series: Self.topMatches(seriesIndex, query: normalizedQuery, limit: limit).map(\.item)
        )
    }

    fileprivate static func topMatches(
        _ items: [IndexedCatalogItem],
        query: String,
        limit: Int
    ) -> [IndexedCatalogItem] {
        var best: [(item: IndexedCatalogItem, score: Int)] = []
        best.reserveCapacity(limit)

        for item in items {
            let itemScore = max(
                SearchText.fuzzyScore(query, text: item.title, stripped: item.strippedTitle),
                SearchText.fuzzyScore(query, text: item.category, stripped: item.category) / 2,
                SearchText.fuzzyScore(query, text: item.genre, stripped: item.genre) / 2
            )
            guard itemScore > 0 else { continue }

            if best.count < limit {
                best.append((item, itemScore))
                continue
            }

            var worstIndex = 0
            for index in 1..<best.count {
                let current = best[index]
                let worst = best[worstIndex]
                if current.score < worst.score ||
                    (current.score == worst.score && current.item.title > worst.item.title) {
                    worstIndex = index
                }
            }

            let worst = best[worstIndex]
            if itemScore > worst.score ||
                (itemScore == worst.score && item.title < worst.item.title) {
                best[worstIndex] = (item, itemScore)
            }
        }

        return best.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.item.title < rhs.item.title }
            return lhs.score > rhs.score
        }
        .map(\.item)
    }

    private static func signature(vods: [XstreamVOD], series: [XstreamSeries]) -> String {
        let vodFirst = vods.first?.id ?? -1
        let vodLast = vods.last?.id ?? -1
        let seriesFirst = series.first?.id ?? -1
        let seriesLast = series.last?.id ?? -1
        return "\(vods.count):\(vodFirst):\(vodLast)|\(series.count):\(seriesFirst):\(seriesLast)"
    }
}

public extension CatalogSnapshot {
    func search(query: String, limit: Int = 30) -> CatalogSearchResults {
        let normalizedQuery = SearchText.normalize(query)
        guard normalizedQuery.count >= 2, limit > 0 else {
            return CatalogSearchResults(movies: [], series: [])
        }

        return CatalogSearchResults(
            movies: CatalogIndex.topMatches(
                vodItems.map(IndexedCatalogItem.init(item:)),
                query: normalizedQuery,
                limit: limit
            ).map(\.item),
            series: CatalogIndex.topMatches(
                seriesItems.map(IndexedCatalogItem.init(item:)),
                query: normalizedQuery,
                limit: limit
            ).map(\.item)
        )
    }
}

public enum CatalogBuilder {
    private static let shelfLimit = 200
    private static let premiumRailLimit = 80

    public static func build(
        vods: [XstreamVOD],
        series: [XstreamSeries]
    ) -> CatalogSnapshot {
        let vodItems = buildVODItems(vods)
        let seriesItems = buildSeriesItems(series)
        let movieGenreSections = buildGenreSections(items: vodItems, kind: .movie)
        let seriesGenreSections = buildGenreSections(items: seriesItems, kind: .series)
        let brandHubSections = buildBrandHubSections(items: vodItems)

        return CatalogSnapshot(
            vodItems: vodItems,
            seriesItems: seriesItems,
            movieSections: buildMovieSections(items: vodItems),
            seriesSections: buildSeriesSections(items: seriesItems),
            movieGenreSections: movieGenreSections,
            seriesGenreSections: seriesGenreSections,
            brandHubSections: brandHubSections,
            movieGenres: movieGenreSections.map(\.title),
            seriesGenres: seriesGenreSections.map(\.title)
        )
    }

    private static func buildVODItems(_ vods: [XstreamVOD]) -> [UnifiedMediaItem] {
        struct Draft {
            var title: String
            var variants: [MediaVariant]
            var tags: Set<VODTag>
            var category: NormalizedContentCategory?
            var rawCategoryName: String?
            var brandHub: BrandHub?
            var rating: String?
            var posterURLString: String?
        }

        var drafts: [String: Draft] = [:]

        for vod in vods {
            let (cleaned, tags) = VODNormalizer.extractTagsAndClean(vod.name)
            let cleanTitle = canonicalMovieTitle(original: vod.name, fallback: cleaned)
            let key = SearchText.stableKey(cleanTitle)
            guard !key.isEmpty else { continue }

            let category = vod.normalizedCategory ?? CategoryNormalizer.normalize(
                rawID: vod.categoryID,
                rawName: vod.rawCategoryName ?? vod.categoryName,
                provider: .xtream,
                contentType: .movie
            )
            if category.role == .adult { continue }

            let rawCategory = category.raw.rawName ?? vod.rawCategoryName ?? vod.categoryName ?? category.displayName
            let hub = VODNormalizer.mapCategoryToHub(categoryName: rawCategory)
            let variant = CatalogVariantSelector.mediaVariant(for: vod, cleanTitle: cleanTitle, tags: tags)

            if var draft = drafts[key] {
                if !draft.variants.contains(where: { $0.providerID == vod.id }) {
                    draft.variants.append(variant)
                }
                draft.tags.formUnion(tags)
                draft.rating = betterRating(draft.rating, vod.rating)
                if draft.posterURLString == nil { draft.posterURLString = vod.streamIcon }
                if draft.category?.isPrimaryVisible != true, category.isPrimaryVisible {
                    draft.category = category
                    draft.rawCategoryName = rawCategory
                    draft.brandHub = hub
                }
                drafts[key] = draft
            } else {
                drafts[key] = Draft(
                    title: cleanTitle,
                    variants: [variant],
                    tags: tags,
                    category: category,
                    rawCategoryName: rawCategory,
                    brandHub: hub,
                    rating: vod.rating,
                    posterURLString: vod.streamIcon
                )
            }
        }

        return drafts.map { key, draft in
            let variants = CatalogVariantSelector.sortedVariants(draft.variants)
            let primaryPoster = variants.first?.vod?.streamIcon ?? draft.posterURLString
            return UnifiedMediaItem(
                id: "movie-\(key)",
                kind: .movie,
                title: draft.title,
                posterURLString: primaryPoster,
                rating: draft.rating,
                year: nil,
                genre: draft.category?.displayName,
                categoryName: draft.category?.displayName,
                normalizedCategory: draft.category,
                brandHub: draft.brandHub,
                tags: draft.tags,
                variants: variants,
                series: nil
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }

    private static func buildSeriesItems(_ series: [XstreamSeries]) -> [UnifiedMediaItem] {
        var seen = Set<String>()
        var items: [UnifiedMediaItem] = []
        items.reserveCapacity(series.count)

        for show in series {
            let title = VODNormalizer.cleanVODTitle(show.name)
            let cleanTitle = canonicalMovieTitle(original: show.name, fallback: title)
            let key = SearchText.stableKey(cleanTitle)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }

            let category = show.normalizedCategory ?? CategoryNormalizer.normalize(
                rawID: show.categoryID,
                rawName: show.rawCategoryName ?? show.categoryName ?? show.genre,
                provider: .xtream,
                contentType: .series
            )
            if category.role == .adult { continue }

            items.append(
                UnifiedMediaItem(
                    id: "series-\(show.id)",
                    kind: .series,
                    title: cleanTitle,
                    posterURLString: show.cover,
                    rating: show.rating,
                    year: yearString(from: show.releaseDate),
                    genre: show.genre ?? category.displayName,
                    categoryName: category.displayName,
                    normalizedCategory: category,
                    brandHub: nil,
                    tags: [],
                    variants: [],
                    series: show
                )
            )
        }

        return items.sorted { lhs, rhs in
            lhs.title.localizedCompare(rhs.title) == .orderedAscending
        }
    }

    private static func buildMovieSections(items: [UnifiedMediaItem]) -> [CatalogSection] {
        var sections: [CatalogSection] = []
        let topRated = items
            .filter { ratingValue($0.rating) > 0 }
            .sorted { ratingValue($0.rating) > ratingValue($1.rating) }
            .prefix(premiumRailLimit)
        if !topRated.isEmpty {
            sections.append(CatalogSection(
                id: "movie-top-rated",
                title: "Top Rated",
                role: .topRated,
                kind: .movie,
                items: Array(topRated)
            ))
        }

        let ultraHD = items
            .filter { $0.tags.contains(.uhd4k) || $0.tags.contains(.hdr) }
            .prefix(premiumRailLimit)
        if !ultraHD.isEmpty {
            sections.append(CatalogSection(
                id: "movie-4k-hdr",
                title: "4K/HDR",
                role: .ultraHD,
                kind: .movie,
                items: Array(ultraHD)
            ))
        }

        if !items.isEmpty {
            sections.append(CatalogSection(
                id: "movie-all",
                title: "Movies",
                role: .movies,
                kind: .movie,
                items: Array(items.prefix(premiumRailLimit))
            ))
        }

        return sections
    }

    private static func buildSeriesSections(items: [UnifiedMediaItem]) -> [CatalogSection] {
        var sections: [CatalogSection] = []
        let topRated = items
            .filter { ratingValue($0.rating) > 0 }
            .sorted { ratingValue($0.rating) > ratingValue($1.rating) }
            .prefix(premiumRailLimit)

        if !topRated.isEmpty {
            sections.append(CatalogSection(
                id: "series-top-rated",
                title: "Top Rated Series",
                role: .topRated,
                kind: .series,
                items: Array(topRated)
            ))
        }

        if !items.isEmpty {
            sections.append(CatalogSection(
                id: "series-all",
                title: "Series",
                role: .series,
                kind: .series,
                items: Array(items.prefix(premiumRailLimit))
            ))
        }

        return sections
    }

    private static func buildGenreSections(
        items: [UnifiedMediaItem],
        kind: CatalogMediaKind
    ) -> [CatalogSection] {
        var grouped: [String: [UnifiedMediaItem]] = [:]
        for item in items {
            guard let category = item.normalizedCategory, category.isPrimaryVisible else { continue }
            grouped[category.displayName, default: []].append(item)
        }

        return grouped.keys.sorted().compactMap { genre in
            guard var genreItems = grouped[genre], !genreItems.isEmpty else { return nil }
            genreItems.sort { lhs, rhs in
                let leftRating = ratingValue(lhs.rating)
                let rightRating = ratingValue(rhs.rating)
                if leftRating != rightRating { return leftRating > rightRating }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
            return CatalogSection(
                id: "\(kind.rawValue)-genre-\(SearchText.stableKey(genre))",
                title: genre,
                role: .genre,
                kind: kind,
                items: Array(genreItems.prefix(shelfLimit))
            )
        }
    }

    private static func buildBrandHubSections(items: [UnifiedMediaItem]) -> [CatalogHubSection] {
        var grouped: [BrandHub: [String: [UnifiedMediaItem]]] = [:]

        for item in items {
            guard let hub = item.brandHub, let category = item.normalizedCategory else { continue }
            let rawCategoryName = category.raw.rawName ?? category.displayName
            let shelfName = VODNormalizer.normalizeShelfName(categoryName: rawCategoryName, hub: hub)
            grouped[hub, default: [:]][shelfName, default: []].append(item)
        }

        return BrandHub.allCases.compactMap { hub in
            guard let shelves = grouped[hub] else { return nil }
            let sections = shelves.keys.sorted().compactMap { shelfName -> CatalogSection? in
                guard var shelfItems = shelves[shelfName], !shelfItems.isEmpty else { return nil }
                shelfItems.sort { lhs, rhs in
                    lhs.title.localizedCompare(rhs.title) == .orderedAscending
                }
                return CatalogSection(
                    id: "hub-\(hub.id)-\(SearchText.stableKey(shelfName))",
                    title: shelfName,
                    role: .platformHub,
                    kind: .movie,
                    hub: hub,
                    items: Array(shelfItems.prefix(shelfLimit))
                )
            }
            return sections.isEmpty ? nil : CatalogHubSection(hub: hub, sections: sections)
        }
    }

    private static func betterRating(_ lhs: String?, _ rhs: String?) -> String? {
        let left = ratingValue(lhs)
        let right = ratingValue(rhs)
        if right > left { return rhs }
        return lhs ?? rhs
    }

    private static func ratingValue(_ value: String?) -> Double {
        guard let value else { return 0 }
        return Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func yearString(from releaseDate: String?) -> String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }

    private static func canonicalMovieTitle(original: String, fallback: String) -> String {
        let fallbackLooksBroken = fallback.isEmpty
            || fallback.contains("]")
            || fallback.contains("[")
            || fallback.count < 3
        var value = fallbackLooksBroken ? original : fallback

        value = value.replacingOccurrences(
            of: #"(?i)\s*[\[\(\{]\s*(?:PL\s*DUB|DUB\s*PL|LEKTOR\s*PL|PL\s*SUB|SUB\s*PL|NAPISY|EN\s*SUB|SUB\s*EN|PL|EN|DE|FR|IT|ES|TR|RU|4K|UHD|FHD|HD|HDR|SD|2160P|1080P|720P|HEVC|H265|H264)\s*[\]\)\}]\s*"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)^(?:PL\s*DUB|DUB\s*PL|PL\s*SUB|SUB\s*PL|LEKTOR\s*PL|NAPISY|PL|EN|DE|FR|IT|ES|TR|RU|4K|UHD|FHD|HD|HDR|2160P|1080P|720P)\s*(?:-|:|\|)\s*"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?i)\s+(?:PL\s*DUB|DUB\s*PL|PL\s*SUB|SUB\s*PL|LEKTOR\s*PL|NAPISY|PL|EN|DE|FR|IT|ES|TR|RU|4K|UHD|FHD|HD|HDR|2160P|1080P|720P)$"#,
            with: "",
            options: .regularExpression
        )
        return value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct IndexedCatalogItem: Sendable {
    let item: UnifiedMediaItem
    let title: String
    let strippedTitle: String
    let category: String
    let genre: String

    init(item: UnifiedMediaItem) {
        self.item = item
        self.title = SearchText.normalize(item.title)
        self.strippedTitle = SearchText.strippedTitle(self.title)
        self.category = SearchText.normalize(item.categoryName ?? "")
        self.genre = SearchText.normalize(item.genre ?? "")
    }
}

enum SearchText {
    static func stableKey(_ value: String) -> String {
        normalize(value)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func strippedTitle(_ value: String) -> String {
        var result = value
        for _ in 0..<3 {
            if let range = result.range(
                of: #"^[a-z0-9\+\-\.]{1,10}[\s]*[\-\|][\s]+"#,
                options: [.regularExpression, .caseInsensitive]
            ) {
                result.removeSubrange(range)
            } else {
                break
            }
        }
        return result
    }

    static func fuzzyScore(_ query: String, text: String, stripped: String) -> Int {
        guard !query.isEmpty, !text.isEmpty else { return 0 }
        if stripped == query { return 200 }
        if text == query { return 190 }
        if stripped.hasPrefix(query) || text.hasPrefix(query) { return 150 }
        if stripped.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 120 }
        if text.contains(query) { return 100 }
        if stripped.contains(query) { return 90 }

        var queryIndex = query.startIndex
        for character in stripped {
            if queryIndex < query.endIndex && character == query[queryIndex] {
                queryIndex = query.index(after: queryIndex)
            }
        }
        if queryIndex == query.endIndex {
            let score = Int(Double(query.count) / Double(max(stripped.count, 1)) * 80)
            return max(1, min(80, score))
        }
        return 0
    }
}
