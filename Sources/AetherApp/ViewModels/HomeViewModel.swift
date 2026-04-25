import SwiftUI
import AetherCore

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var isPhase1Loaded = false
    @Published var isFullyLoaded = false
    @Published var heroBannerItems: [HeroBannerItem] = []
    @Published var shelves: [(title: String, items: [ShelfItem])] = []
    @Published var seriesShelves: [(title: String, items: [ShelfItem])] = []
    @Published var liveItems: [ShelfItem] = []
    @Published var allVODs: [XstreamVOD] = []
    @Published var allSeries: [XstreamSeries] = []
    @Published var errorMessage: String? = nil
    @Published var error: Error? = nil

    // Priority-sorted VOD shelves exposed to VODBrowserView
    @Published var streamingServiceShelves: [(title: String, icon: String, items: [ShelfItem], allItems: [ShelfItem])] = []
    @Published var genreShelves: [(title: String, items: [ShelfItem])] = []

    // Static cache — shared across views, survives navigation
    static var cachedVODShelves: [(title: String, items: [ShelfItem])]? = nil
    static var cachedSeriesShelves: [(title: String, items: [ShelfItem])]? = nil
    static var cachedLive: [ShelfItem]? = nil
    static var cachedAllVODs: [XstreamVOD]? = nil
    static var cachedAllSeries: [XstreamSeries]? = nil

    // MARK: - Disk cache keys
    private static let cacheKey = "homevm_shelves_v1"
    private static let cacheAgeKey = "homevm_cache_age_v1"
    private static let maxCacheAge: TimeInterval = 3600 // 1 hour

    private var service: XstreamService?
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    @AppStorage("preferredLanguage") var preferredLanguage: String = "pl"
    @AppStorage("preferredCountry") var preferredCountry: String = "PL"

    var sharedService: XstreamService? { service }

    /// Returns all items for a streaming service shelf by title.
    func allItemsForService(_ title: String) -> [ShelfItem] {
        streamingServiceShelves.first(where: { $0.title == title })?.allItems ?? []
    }

    /// Re-sorts shelves using current language/country preference.
    func rebuildWithCurrentPreferences() {
        rebuildPriorityShelves(from: shelves)
    }

    func loadIfNeeded() {
        guard !hasLoaded, let svc = service else { return }
        hasLoaded = true
        loadTask = Task { await performLoad(svc) }
    }

    func load(credentials: XstreamCredentials) {
        if service == nil {
            service = XstreamService(credentials: credentials)
        }

        // INSTANT: show disk cache before even starting network load
        if shelves.isEmpty, let diskCached = Self.loadFromDiskCache() {
            shelves = diskCached
            heroBannerItems = Self.buildHeroBanner(from: diskCached)
            rebuildPriorityShelves(from: diskCached)
            isPhase1Loaded = true
        }

        // Restore from in-memory cache if already loaded
        if hasLoaded {
            if !shelves.isEmpty { return }
            if let cached = Self.cachedVODShelves {
                shelves = cached
                heroBannerItems = Self.buildHeroBanner(from: cached)
                rebuildPriorityShelves(from: cached)
                isPhase1Loaded = true
            }
            if let cached = Self.cachedSeriesShelves { seriesShelves = cached }
            if let cached = Self.cachedLive { liveItems = cached }
            if let cached = Self.cachedAllVODs { allVODs = cached }
            if let cached = Self.cachedAllSeries { allSeries = cached }
            isFullyLoaded = true
            return
        }
        hasLoaded = true
        guard let svc = service else { return }
        loadTask = Task { await performLoad(svc) }
    }

    func forceReload(credentials: XstreamCredentials) {
        hasLoaded = false
        loadTask?.cancel()
        service = nil
        Self.cachedVODShelves = nil
        Self.cachedSeriesShelves = nil
        Self.cachedLive = nil
        Self.cachedAllVODs = nil
        Self.cachedAllSeries = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheAgeKey)
        heroBannerItems = []
        shelves = []
        seriesShelves = []
        streamingServiceShelves = []
        genreShelves = []
        liveItems = []
        allVODs = []
        allSeries = []
        isPhase1Loaded = false
        isFullyLoaded = false
        load(credentials: credentials)
    }

    private func performLoad(_ svc: XstreamService) async {
        // TIER 0: disk cache already shown by load() — skip if already populated
        defer {
            // If the task was cancelled before completion, allow load() to retry
            if Task.isCancelled { hasLoaded = false }
        }

        // Fetch all categories — propagate to UI on failure
        let allCats: [XstreamCategory]
        do {
            allCats = try await svc.vodCategories()
        } catch {
            self.error = error
            self.errorMessage = error.localizedDescription
            isPhase1Loaded = true
            return
        }
        let filtered = allCats.filter { !isGarbageCategory($0.name) }

        // Sort: streaming services first, then alphabetically
        let sorted = filtered.sorted { a, b in
            let aIsService = Self.streamingServices.contains { entry in
                entry.keywords.contains { a.name.lowercased().contains($0) }
            }
            let bIsService = Self.streamingServices.contains { entry in
                entry.keywords.contains { b.name.lowercased().contains($0) }
            }
            if aIsService != bIsService { return aIsService }
            return a.name < b.name
        }

        let top16 = Array(sorted.prefix(16))
        guard !top16.isEmpty else { isPhase1Loaded = true; return }

        // TIER 1: First 3 categories IN PARALLEL (async let)
        let cats3 = Array(top16.prefix(3))
        async let shelf0 = loadVODShelf(svc: svc, cat: cats3[0])
        async let shelf1 = cats3.count > 1 ? loadVODShelf(svc: svc, cat: cats3[1]) : nil
        async let shelf2 = cats3.count > 2 ? loadVODShelf(svc: svc, cat: cats3[2]) : nil

        let (r0, r1, r2) = await (shelf0, shelf1, shelf2)
        var initialShelves: [(title: String, items: [ShelfItem])] = []
        if let r = r0 { initialShelves.append(r) }
        if let r = r1 { initialShelves.append(r) }
        if let r = r2 { initialShelves.append(r) }

        if !initialShelves.isEmpty {
            shelves = initialShelves
            heroBannerItems = Self.buildHeroBanner(from: initialShelves)
            rebuildPriorityShelves(from: initialShelves)
            allVODs = initialShelves.flatMap { $0.items.compactMap { $0.vod } }
            isPhase1Loaded = true
        } else {
            isPhase1Loaded = true
        }

        // TIER 2: Remaining categories with TaskGroup (concurrent)
        var allShelves = initialShelves
        var collectedVODs: [XstreamVOD] = allVODs

        await withTaskGroup(of: (title: String, items: [ShelfItem])?.self) { group in
            for cat in top16.dropFirst(3) {
                group.addTask { await self.loadVODShelf(svc: svc, cat: cat) }
            }
            for await shelf in group {
                if let s = shelf {
                    allShelves.append(s)
                    shelves = allShelves
                    rebuildPriorityShelves(from: allShelves)
                    collectedVODs.append(contentsOf: s.items.compactMap { $0.vod })
                    allVODs = collectedVODs
                }
            }
        }

        Self.cachedVODShelves = allShelves
        Self.cachedAllVODs = collectedVODs
        heroBannerItems = Self.buildHeroBanner(from: allShelves)

        // Save to disk cache for next launch
        Self.saveToDiskCache(allShelves)

        // TIER 3: Series + Live in background (don't block)
        async let seriesTask: Void = loadSeriesInBackground(svc)
        async let liveTask: Void = loadLiveInBackground(svc)
        await seriesTask
        await liveTask

        // TIER 4: Full search index — loads ALL remaining VOD categories (beyond top 16) into allVODs.
        // Runs detached so it never blocks UI or series/live loading.
        // allVODs is already partially filled from Tier 1+2; this appends the rest.
        let top16IDs = Set(top16.map { $0.id })
        let remainingCats = allCats.filter { !self.isGarbageCategory($0.name) && !top16IDs.contains($0.id) }
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            var extra: [XstreamVOD] = []
            let batchSize = 4  // 4 concurrent requests — won't saturate the connection during playback
            let cats = remainingCats
            var i = 0
            while i < cats.count {
                guard await self.canContinueIndexing() else { break }
                let batch = Array(cats[i..<min(i + batchSize, cats.count)])
                await withTaskGroup(of: [XstreamVOD].self) { group in
                    for cat in batch {
                        group.addTask { (try? await svc.vodStreams(categoryID: cat.id)) ?? [] }
                    }
                    for await vods in group { extra.append(contentsOf: vods) }
                }
                i += batchSize
                // 200ms pause between batches — lets the OS scheduler breathe for active playback
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !extra.isEmpty else { return }
            await MainActor.run {
                self.allVODs.append(contentsOf: extra)
                Self.cachedAllVODs = self.allVODs
                print("[HomeVM] Search index complete — \(self.allVODs.count) VODs indexed")
            }
        }

        isFullyLoaded = true
    }

    /// Guard for Tier 4 batched indexing. Returns false to abort indexing early (e.g., could
    /// be extended to pause when user is actively watching a stream).
    private func canContinueIndexing() async -> Bool {
        return !Task.isCancelled
    }

    private func loadSeriesInBackground(_ svc: XstreamService) async {
        let allSeriesCats = (try? await svc.seriesCategories()) ?? []
        let clean = allSeriesCats.filter { !isGarbageCategory($0.name) }.sorted { $0.name < $1.name }
        var results: [(title: String, items: [ShelfItem])] = []
        var collected: [XstreamSeries] = []

        await withTaskGroup(of: (title: String, items: [ShelfItem])?.self) { group in
            for cat in clean.prefix(8) {
                group.addTask { await self.loadSeriesShelf(svc: svc, cat: cat) }
            }
            for await shelf in group {
                if let s = shelf {
                    results.append(s)
                    seriesShelves = results
                    collected.append(contentsOf: s.items.compactMap { $0.series })
                    allSeries = collected
                }
            }
        }
        Self.cachedSeriesShelves = results
        Self.cachedAllSeries = collected
    }

    private func loadLiveInBackground(_ svc: XstreamService) async {
        let streams = (try? await svc.liveStreams()) ?? []
        let items = streams.prefix(20).map { stream in
            ShelfItem(id: "\(stream.id)", title: stream.name, imageURL: stream.streamIcon, stream: stream, onTap: {})
        }
        liveItems = Array(items)
        Self.cachedLive = Array(items)
    }

    // MARK: - Disk cache

    static func loadFromDiskCache() -> [(title: String, items: [ShelfItem])]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let age = UserDefaults.standard.object(forKey: cacheAgeKey) as? Date,
              Date().timeIntervalSince(age) < maxCacheAge,
              let decoded = try? JSONDecoder().decode([CachedShelf].self, from: data)
        else { return nil }
        return decoded.map { cs in
            (title: cs.title, items: cs.items.map { ci in
                ShelfItem(id: ci.id, title: ci.title, imageURL: ci.imageURL, onTap: {})
            })
        }
    }

    static func saveToDiskCache(_ shelves: [(title: String, items: [ShelfItem])]) {
        let cached = shelves.map { s in
            CachedShelf(title: s.title, items: s.items.map { i in
                CachedShelfItem(id: i.id, title: i.title, imageURL: i.imageURL)
            })
        }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheAgeKey)
        }
    }

    struct CachedShelf: Codable {
        let title: String
        let items: [CachedShelfItem]
    }

    struct CachedShelfItem: Codable {
        let id: String
        let title: String
        let imageURL: String?
    }

    // MARK: - Priority shelf buckets

    /// Streaming service keyword map: (keywords, display label, SF Symbol icon)
    private static let streamingServices: [(keywords: [String], label: String, icon: String)] = [
        (["netflix", " nf ", "nf-", "-nf "], "Netflix", "n.circle.fill"),
        (["prime", "amazon"], "Prime Video", "p.circle.fill"),
        (["apple tv", "appletv", "apple+"], "Apple TV+", "apple.logo"),
        (["hbo"], "HBO Max", "h.circle.fill"),
        (["disney"], "Disney+", "d.circle.fill"),
        (["hulu"], "Hulu", "h.square.fill"),
        (["paramount"], "Paramount+", "p.square.fill"),
    ]

    /// Genre keyword map: (keywords, display label)
    private static let genreKeywords: [(keywords: [String], label: String)] = [
        (["action", "akcja", "thriller"], "Akcja & Thriller"),
        (["comedy", "komedia"], "Komedia"),
        (["horror"], "Horror"),
        (["sci-fi", " sf ", "science fiction"], "Sci-Fi"),
        (["drama", "dramat"], "Dramat"),
        (["animation", "animacja", "animated"], "Animacja"),
        (["documentary", "dokument"], "Dokumentalne"),
        (["kids", "family", "dla dzieci", "children"], "Dla dzieci"),
        (["romance", "romans"], "Romans"),
        (["4k"], "4K Filmy"),
        (["polish", "polski", " pl "], "🇵🇱 Polskie"),
        (["turkish", "turecki", " tr "], "🇹🇷 Tureckie"),
    ]

    /// Rebuilds `streamingServiceShelves` and `genreShelves` from the flat shelves list.
    private func rebuildPriorityShelves(from shelves: [(title: String, items: [ShelfItem])]) {
        var streaming: [(title: String, icon: String, items: [ShelfItem], allItems: [ShelfItem])] = []
        var genre: [(title: String, items: [ShelfItem])] = []
        var used = Set<String>()

        // Country-boost keywords: preferred country content sorts first in genre shelves
        let countryBoostKeywords: [String]
        switch preferredCountry.uppercased() {
        case "PL": countryBoostKeywords = ["pl", "polish", "polski", "poland"]
        case "TR": countryBoostKeywords = ["tr", "turkish", "turecki"]
        case "DE": countryBoostKeywords = ["de", "german", "deutsch"]
        case "FR": countryBoostKeywords = ["fr", "french", "français"]
        case "ES": countryBoostKeywords = ["es", "spanish", "español"]
        case "AR": countryBoostKeywords = ["ar", "arabic", "عربي"]
        default:   countryBoostKeywords = ["en", "english"]
        }

        // Sort shelves so preferred country genres appear first
        let sortedShelves = shelves.sorted { a, b in
            let aLower = a.title.lowercased()
            let bLower = b.title.lowercased()
            let aBoost = countryBoostKeywords.contains(where: { aLower.contains($0) })
            let bBoost = countryBoostKeywords.contains(where: { bLower.contains($0) })
            if aBoost != bBoost { return aBoost }
            return false
        }

        for shelf in sortedShelves {
            let lower = shelf.title.lowercased()
            if let svc = Self.streamingServices.first(where: { $0.keywords.contains(where: { lower.contains($0) }) }) {
                if !used.contains(svc.label) {
                    let allItems = shelf.items
                    let displayItems = Array(allItems.prefix(8))
                    streaming.append((title: svc.label, icon: svc.icon, items: displayItems, allItems: allItems))
                    used.insert(svc.label)
                }
            } else if let g = Self.genreKeywords.first(where: { $0.keywords.contains(where: { lower.contains($0) }) }) {
                if !used.contains(g.label) {
                    genre.append((title: g.label, items: Array(shelf.items.prefix(8))))
                    used.insert(g.label)
                }
            }
        }

        streamingServiceShelves = streaming
        genreShelves = genre
    }

    private func loadVODShelf(svc: XstreamService, cat: XstreamCategory) async -> (title: String, items: [ShelfItem])? {
        guard let streams = try? await svc.vodStreams(categoryID: cat.id), !streams.isEmpty else { return nil }
        let cleanName = cleanCategoryName(cat.name)
        let items = streams.prefix(20).map { vod in
            ShelfItem(id: "\(vod.id)", title: cleanTitle(vod.name), imageURL: vod.streamIcon, vod: vod, onTap: {})
        }
        return (cleanName, Array(items))
    }

    private func loadSeriesShelf(svc: XstreamService, cat: XstreamSeriesCategory) async -> (title: String, items: [ShelfItem])? {
        guard let series = try? await svc.seriesList(categoryID: cat.id), !series.isEmpty else { return nil }
        let cleanName = cleanCategoryName(cat.name)
        let items = series.prefix(20).map { s in
            ShelfItem(id: "\(s.id)", title: cleanTitle(s.name), imageURL: s.cover, series: s, onTap: {})
        }
        return (cleanName, Array(items))
    }

    private static func buildHeroBanner(from shelves: [(title: String, items: [ShelfItem])]) -> [HeroBannerItem] {
        guard let first = shelves.first else { return [] }
        return first.items.prefix(5).map { item in
            HeroBannerItem(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
        }
    }

    func cleanTitle(_ title: String) -> String {
        let prefixes = ["AMZ - ", "AMZ-", "NF - ", "NF-", "NETFLIX - ", "Netflix - ",
                        "Netflix 4K Premium - ", "Netflix 4K - ",
                        "4K - ", "HD - ", "FHD - ", "UHD - "]
        var result = title
        for prefix in prefixes {
            if result.uppercased().hasPrefix(prefix.uppercased()) {
                result = String(result.dropFirst(prefix.count))
                break
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    func cleanCategoryName(_ name: String) -> String {
        var clean = name

        // Strip leading prefix patterns: "PL - ", "TR - ", "AR-TR-D - ", "NF - ", "4K-TOP - " etc.
        let prefixPatterns = ["AR-TR-D - ", "4K-TOP - ", "NF - "]
        for prefix in prefixPatterns {
            if clean.hasPrefix(prefix) {
                clean = String(clean.dropFirst(prefix.count))
                break
            }
        }
        // Generic "XX - " pattern (short prefixes up to 6 chars)
        if let range = clean.range(of: " - ") {
            let prefix = String(clean[..<range.lowerBound])
            if prefix.count <= 6 {
                clean = String(clean[range.upperBound...])
            }
        }

        clean = clean.trimmingCharacters(in: .whitespaces)

        // Add flag emoji based on origin detected in the raw name
        let upper = name.uppercased()
        // Turkish: only if name starts with "TR - " or "TR-" or contains Turkish keywords
        let isTurkish = upper.hasPrefix("TR - ") || upper.hasPrefix("TR-")
            || upper.contains("TURK") || upper.contains("TÜRK") || upper.contains("TURKISH")
        // Polish: only if name starts with "PL - " or "PL-" or contains " PL " (with spaces) or Polish keywords
        let isPolish = upper.hasPrefix("PL - ") || upper.hasPrefix("PL-")
            || upper.contains(" PL ") || upper.contains("POLISH") || upper.contains("POLSKI")
        if isTurkish {
            clean = "🇹🇷 \(clean)"
        } else if isPolish {
            clean = "🇵🇱 \(clean)"
        }

        return clean
    }

    func isGarbageCategory(_ name: String) -> Bool {
        if name.isEmpty { return true }
        // Filter Arabic/RTL script categories
        if name.unicodeScalars.contains(where: { $0.value > 0x0600 && $0.value < 0x06FF }) { return true }
        // Only truly garbage categories — streaming services are KEPT and prioritized
        let garbage = ["adult", "xxx", "18+"]
        let lower = name.lowercased()
        return garbage.contains(where: { lower.contains($0) })
    }
}
