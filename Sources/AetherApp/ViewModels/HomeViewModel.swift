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
    @Published var brandHubs: [(hub: BrandHub, shelves: [(title: String, items: [ShelfItem])])] = []

    // Static cache — shared across views, survives navigation
    static var cachedVODShelves: [(title: String, items: [ShelfItem])]? = nil
    static var cachedSeriesShelves: [(title: String, items: [ShelfItem])]? = nil
    static var cachedLive: [ShelfItem]? = nil
    static var cachedAllVODs: [XstreamVOD]? = nil
    static var cachedAllSeries: [XstreamSeries]? = nil
    static var cachedBrandHubs: [(hub: BrandHub, shelves: [(title: String, items: [ShelfItem])])]? = nil

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

    /// Re-sorts shelves using current language/country preference.
    func rebuildWithCurrentPreferences() {
        // Handled via data reload if necessary
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
            isPhase1Loaded = true
        }

        // Restore from in-memory cache if already loaded
        if hasLoaded {
            if !shelves.isEmpty { return }
            if let cached = Self.cachedVODShelves {
                shelves = cached
                heroBannerItems = Self.buildHeroBanner(from: cached)
                isPhase1Loaded = true
            }
            if let cachedHubs = Self.cachedBrandHubs { brandHubs = cachedHubs }
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
        Self.cachedBrandHubs = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheAgeKey)
        heroBannerItems = []
        shelves = []
        seriesShelves = []
        brandHubs = []
        liveItems = []
        allVODs = []
        allSeries = []
        isPhase1Loaded = false
        isFullyLoaded = false
        load(credentials: credentials)
    }

    private func performLoad(_ svc: XstreamService) async {
        defer {
            if Task.isCancelled { hasLoaded = false }
        }

        do {
            let (allVODShelves, hubToShelves) = try await loadAllVODsGrouped(svc: svc)
            
            guard !allVODShelves.isEmpty else {
                self.errorMessage = "Brak dostępnych filmów."
                isPhase1Loaded = true
                return
            }
            
            // Limit render to Top 20 Shelves internally to keep UI fast
            let topVODShelves = Array(allVODShelves.prefix(20))
            
            self.shelves = topVODShelves
            self.heroBannerItems = Self.buildHeroBanner(from: topVODShelves)
            
            // Build brandHubs directly from the populated hubToShelves
            var grouped: [BrandHub: [(title: String, items: [ShelfItem])]] = [:]
            for hub in BrandHub.allCases {
                guard let shelvesDict = hubToShelves[hub] else { continue }
                var sortedHubShelves: [(title: String, items: [ShelfItem])] = []
                for shelfName in shelvesDict.keys.sorted() {
                    let items = shelvesDict[shelfName]!.values.sorted { $0.title < $1.title }
                    if !items.isEmpty { sortedHubShelves.append((title: shelfName, items: items)) }
                }
                if !sortedHubShelves.isEmpty { grouped[hub] = sortedHubShelves }
            }
            self.brandHubs = grouped.map { (hub: $0.key, shelves: $0.value) }
                .sorted { $0.hub.rawValue < $1.hub.rawValue }
            self.allVODs = await svc.cachedVods // await required since XstreamService is an actor
            
            Self.cachedVODShelves = topVODShelves
            Self.cachedAllVODs = self.allVODs
            Self.cachedBrandHubs = self.brandHubs
            Self.saveToDiskCache(topVODShelves)
            
            isPhase1Loaded = true
            
            // TIER 3: Series + Live in background
            async let seriesTask: Void = loadSeriesInBackground(svc)
            async let liveTask: Void = loadLiveInBackground(svc)
            await seriesTask
            await liveTask
            
            isFullyLoaded = true
            
        } catch {
            self.error = error
            self.errorMessage = error.localizedDescription
            isPhase1Loaded = true
        }
    }

    private func loadAllVODsGrouped(svc: XstreamService) async throws -> (allShelves: [(title: String, items: [ShelfItem])], hubToShelves: [BrandHub: [String: [String: ShelfItem]]]) {
        // SINGLE REQUEST: one call fetches the entire VOD library.
        // This is orders of magnitude faster than 250 per-category requests and correctly
        // populates svc.cachedVods so the global search works without any extra plumbing.
        let allStreams: [XstreamVOD] = (try? await svc.vodStreams(categoryID: nil)) ?? []

        let allCats = (try? await svc.vodCategories()) ?? []
        let catDict = Dictionary(uniqueKeysWithValues: allCats.map { ($0.id, $0) })

        // hub -> shelfName -> normalizedTitle -> Item
        var hubToShelves: [BrandHub: [String: [String: ShelfItem]]] = [:]

        for vod in allStreams {
            let catName = catDict[vod.categoryID ?? ""]?.name ?? vod.categoryName ?? "Other"
            // Skip garbage categories (Arabic, Telugu, etc.) at the mapping stage
            guard !isGarbageCategory(catName) else { continue }

            let hub = VODNormalizer.mapCategoryToHub(categoryName: catName)
            let shelfName = VODNormalizer.normalizeShelfName(categoryName: catName, hub: hub)

            let (cleanTitle, tags) = VODNormalizer.extractTagsAndClean(vod.name)
            let lowerTitle = cleanTitle.lowercased()

            var shelfDict = hubToShelves[hub]?[shelfName] ?? [:]

            if var existing = shelfDict[lowerTitle] {
                existing.tags.formUnion(tags)
                if !existing.alternateVODs.contains(where: { $0.id == vod.id }) {
                    existing.alternateVODs.append(vod)
                }
                shelfDict[lowerTitle] = existing
            } else {
                if shelfDict.count >= 200 { continue }
                let item = ShelfItem(id: "\(vod.id)", title: cleanTitle, imageURL: vod.streamIcon, vod: vod, tags: tags, alternateVODs: [vod], onTap: {})
                shelfDict[lowerTitle] = item
            }

            var shelvesForHub = hubToShelves[hub] ?? [:]
            shelvesForHub[shelfName] = shelfDict
            hubToShelves[hub] = shelvesForHub
        }

        var finalShelves: [(title: String, items: [ShelfItem])] = []
        for hub in BrandHub.allCases {
            guard let shelvesDict = hubToShelves[hub] else { continue }
            for shelfName in shelvesDict.keys.sorted() {
                let items = shelvesDict[shelfName]!.values.sorted { $0.title < $1.title }
                if !items.isEmpty {
                    finalShelves.append((title: shelfName, items: items))
                }
            }
        }

        // Expose flat list for search — already cached inside the actor via vodStreams(nil)
        Self.cachedAllVODs = allStreams

        return (finalShelves, hubToShelves)
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


    // Rebuild Hubs function removed because it's handled properly inside performLoad using raw category keys



    private func loadSeriesShelf(svc: XstreamService, cat: XstreamSeriesCategory) async -> (title: String, items: [ShelfItem])? {
        guard let series = try? await svc.seriesList(categoryID: cat.id), !series.isEmpty else { return nil }
        let cleanName = VODNormalizer.cleanVODTitle(cat.name)
        let items = series.prefix(20).map { s in
            ShelfItem(id: "\(s.id)", title: VODNormalizer.cleanVODTitle(s.name), imageURL: s.cover, series: s, onTap: {})
        }
        return (cleanName, Array(items))
    }

    private static func buildHeroBanner(from shelves: [(title: String, items: [ShelfItem])]) -> [HeroBannerItem] {
        guard let first = shelves.first else { return [] }
        return first.items.prefix(5).map { item in
            HeroBannerItem(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
        }
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
