import SwiftUI
import AetherCore

private struct SeriesShelfPayload: Sendable {
    let title: String
    let series: [XstreamSeries]
}

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

    // Static cache — shared across views, but partitioned by server/account.
    static var cachedVODShelves: [String: [(title: String, items: [ShelfItem])]] = [:]
    static var cachedSeriesShelves: [String: [(title: String, items: [ShelfItem])]] = [:]
    static var cachedLive: [String: [ShelfItem]] = [:]
    static var cachedAllVODs: [String: [XstreamVOD]] = [:]
    static var cachedAllSeries: [String: [XstreamSeries]] = [:]
    static var cachedBrandHubs: [String: [(hub: BrandHub, shelves: [(title: String, items: [ShelfItem])])]] = [:]

    // MARK: - Disk cache keys
    private static let baseDiskCacheKey = "homevm_shelves_v1"
    private static let baseDiskCacheAgeKey = "homevm_cache_age_v1"
    private static let maxCacheAge: TimeInterval = 3600 // 1 hour

    private var service: XstreamService?
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?
    private var activeCacheKey: String?

    @AppStorage("preferredLanguage") var preferredLanguage: String = "pl"
    @AppStorage("preferredCountry") var preferredCountry: String = "PL"

    var sharedService: XstreamService? { service }

    /// Re-sorts shelves using current language/country preference.
    func rebuildWithCurrentPreferences() {
        // Handled via data reload if necessary
    }

    func loadIfNeeded() {
        guard !hasLoaded, let svc = service, let cacheKey = activeCacheKey else { return }
        hasLoaded = true
        loadTask = Task { await performLoad(svc, cacheKey: cacheKey) }
    }

    func load(credentials: XstreamCredentials) {
        let cacheKey = Self.accountCacheKey(for: credentials)

        if activeCacheKey != cacheKey {
            loadTask?.cancel()
            resetLoadedState()
            activeCacheKey = cacheKey
            service = XstreamService(credentials: credentials)
        } else if service == nil {
            service = XstreamService(credentials: credentials)
        }

        // INSTANT: show disk cache before even starting network load
        if shelves.isEmpty, let diskCached = Self.loadFromDiskCache(cacheKey: cacheKey) {
            shelves = diskCached
            heroBannerItems = Self.buildHeroBanner(from: diskCached)
            isPhase1Loaded = true
        }

        // Restore from in-memory cache if already loaded
        if hasLoaded {
            if !shelves.isEmpty { return }
            if let cached = Self.cachedVODShelves[cacheKey] {
                shelves = cached
                heroBannerItems = Self.buildHeroBanner(from: cached)
                isPhase1Loaded = true
            }
            if let cachedHubs = Self.cachedBrandHubs[cacheKey] { brandHubs = cachedHubs }
            if let cached = Self.cachedSeriesShelves[cacheKey] { seriesShelves = cached }
            if let cached = Self.cachedLive[cacheKey] { liveItems = cached }
            if let cached = Self.cachedAllVODs[cacheKey] { allVODs = cached }
            if let cached = Self.cachedAllSeries[cacheKey] { allSeries = cached }
            isFullyLoaded = true
            return
        }
        hasLoaded = true
        guard let svc = service else { return }
        loadTask = Task { await performLoad(svc, cacheKey: cacheKey) }
    }

    func forceReload(credentials: XstreamCredentials) {
        let cacheKey = Self.accountCacheKey(for: credentials)
        loadTask?.cancel()
        service = nil
        activeCacheKey = nil
        hasLoaded = false
        Self.cachedVODShelves.removeValue(forKey: cacheKey)
        Self.cachedSeriesShelves.removeValue(forKey: cacheKey)
        Self.cachedLive.removeValue(forKey: cacheKey)
        Self.cachedAllVODs.removeValue(forKey: cacheKey)
        Self.cachedAllSeries.removeValue(forKey: cacheKey)
        Self.cachedBrandHubs.removeValue(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.diskCacheKey(for: cacheKey))
        UserDefaults.standard.removeObject(forKey: Self.diskCacheAgeKey(for: cacheKey))
        resetLoadedState()
        load(credentials: credentials)
    }

    private func performLoad(_ svc: XstreamService, cacheKey: String) async {
        defer {
            if Task.isCancelled { hasLoaded = false }
        }

        do {
            let (allVODShelves, hubToShelves) = try await loadAllVODsGrouped(svc: svc, cacheKey: cacheKey)
            guard isActive(cacheKey) else { return }
            
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
            guard isActive(cacheKey) else { return }
            
            Self.cachedVODShelves[cacheKey] = topVODShelves
            Self.cachedAllVODs[cacheKey] = self.allVODs
            Self.cachedBrandHubs[cacheKey] = self.brandHubs
            Self.saveToDiskCache(topVODShelves, cacheKey: cacheKey)
            
            isPhase1Loaded = true
            
            // TIER 3: Series + Live in background
            async let seriesTask: Void = loadSeriesInBackground(svc, cacheKey: cacheKey)
            async let liveTask: Void = loadLiveInBackground(svc, cacheKey: cacheKey)
            await seriesTask
            await liveTask
            guard isActive(cacheKey) else { return }
            
            isFullyLoaded = true
            
        } catch {
            guard isActive(cacheKey) else { return }
            self.error = error
            self.errorMessage = error.localizedDescription
            isPhase1Loaded = true
        }
    }

    private func loadAllVODsGrouped(svc: XstreamService, cacheKey: String) async throws -> (allShelves: [(title: String, items: [ShelfItem])], hubToShelves: [BrandHub: [String: [String: ShelfItem]]]) {
        // SINGLE REQUEST: one call fetches the entire VOD library.
        // This is orders of magnitude faster than 250 per-category requests and correctly
        // populates svc.cachedVods so the global search works without any extra plumbing.
        let allStreams: [XstreamVOD] = (try? await svc.vodStreams(categoryID: nil)) ?? []

        // hub -> shelfName -> normalizedTitle -> Item
        var hubToShelves: [BrandHub: [String: [String: ShelfItem]]] = [:]

        for vod in allStreams {
            let category = vod.normalizedCategory ?? CategoryNormalizer.normalize(
                rawID: vod.categoryID,
                rawName: vod.rawCategoryName ?? vod.categoryName,
                provider: .xtream,
                contentType: .movie
            )
            guard category.isPrimaryVisible else { continue }

            let sourceCategoryName = category.raw.rawName ?? category.displayName
            let hub = VODNormalizer.mapCategoryToHub(categoryName: sourceCategoryName)
            let shelfName = VODNormalizer.normalizeShelfName(categoryName: sourceCategoryName, hub: hub)

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
        Self.cachedAllVODs[cacheKey] = allStreams

        return (finalShelves, hubToShelves)
    }

    private func loadSeriesInBackground(_ svc: XstreamService, cacheKey: String) async {
        let allSeriesCats = (try? await svc.seriesCategories()) ?? []
        let clean = allSeriesCats
            .filter {
                CategoryNormalizer.isPrimaryCategoryVisible(
                    $0.name,
                    rawID: $0.id,
                    provider: .xtream,
                    contentType: .series
                )
            }
            .sorted { $0.name < $1.name }
        var results: [(title: String, items: [ShelfItem])] = []
        var collected: [XstreamSeries] = []

        await withTaskGroup(of: SeriesShelfPayload?.self) { group in
            for cat in clean.prefix(8) {
                group.addTask { await Self.loadSeriesShelfPayload(svc: svc, cat: cat) }
            }
            for await payload in group {
                guard isActive(cacheKey) else { return }
                if let payload {
                    let items = payload.series.map { series in
                        ShelfItem(id: "\(series.id)", title: VODNormalizer.cleanVODTitle(series.name), imageURL: series.cover, series: series, onTap: {})
                    }
                    let shelf = (title: payload.title, items: items)
                    results.append(shelf)
                    seriesShelves = results
                    collected.append(contentsOf: payload.series)
                    allSeries = collected
                }
            }
        }
        guard isActive(cacheKey) else { return }
        Self.cachedSeriesShelves[cacheKey] = results
        Self.cachedAllSeries[cacheKey] = collected
    }

    private func loadLiveInBackground(_ svc: XstreamService, cacheKey: String) async {
        let streams = (try? await svc.liveStreams()) ?? []
        guard isActive(cacheKey) else { return }
        let items = streams.prefix(20).map { stream in
            ShelfItem(id: "\(stream.id)", title: stream.name, imageURL: stream.streamIcon, stream: stream, onTap: {})
        }
        liveItems = Array(items)
        Self.cachedLive[cacheKey] = Array(items)
    }

    // MARK: - Disk cache

    static func loadFromDiskCache(cacheKey: String) -> [(title: String, items: [ShelfItem])]? {
        guard let data = UserDefaults.standard.data(forKey: diskCacheKey(for: cacheKey)),
              let age = UserDefaults.standard.object(forKey: diskCacheAgeKey(for: cacheKey)) as? Date,
              Date().timeIntervalSince(age) < maxCacheAge,
              let decoded = try? JSONDecoder().decode([CachedShelf].self, from: data)
        else { return nil }
        return decoded.map { cs in
            (title: cs.title, items: cs.items.map { ci in
                ShelfItem(id: ci.id, title: ci.title, imageURL: ci.imageURL, onTap: {})
            })
        }
    }

    static func saveToDiskCache(_ shelves: [(title: String, items: [ShelfItem])], cacheKey: String) {
        let cached = shelves.map { s in
            CachedShelf(title: s.title, items: s.items.map { i in
                CachedShelfItem(id: i.id, title: i.title, imageURL: i.imageURL)
            })
        }
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: diskCacheKey(for: cacheKey))
            UserDefaults.standard.set(Date(), forKey: diskCacheAgeKey(for: cacheKey))
        }
    }

    private func resetLoadedState() {
        hasLoaded = false
        heroBannerItems = []
        shelves = []
        seriesShelves = []
        brandHubs = []
        liveItems = []
        allVODs = []
        allSeries = []
        isPhase1Loaded = false
        isFullyLoaded = false
        errorMessage = nil
        error = nil
    }

    private func isActive(_ cacheKey: String) -> Bool {
        activeCacheKey == cacheKey && !Task.isCancelled
    }

    private static func accountCacheKey(for credentials: XstreamCredentials) -> String {
        var components = URLComponents(url: credentials.baseURL, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        let base = components?.url?.absoluteString ?? credentials.baseURL.absoluteString
        return "\(base)|\(credentials.username)"
    }

    private static func diskCacheKey(for accountKey: String) -> String {
        "\(baseDiskCacheKey)_\(stableHash(accountKey))"
    }

    private static func diskCacheAgeKey(for accountKey: String) -> String {
        "\(baseDiskCacheAgeKey)_\(stableHash(accountKey))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
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



    nonisolated private static func loadSeriesShelfPayload(svc: XstreamService, cat: XstreamSeriesCategory) async -> SeriesShelfPayload? {
        guard let series = try? await svc.seriesList(categoryID: cat.id), !series.isEmpty else { return nil }
        let cleanName = CategoryNormalizer.normalize(
            rawID: cat.id,
            rawName: cat.name,
            provider: .xtream,
            contentType: .series
        ).displayName
        return SeriesShelfPayload(title: cleanName, series: Array(series.prefix(20)))
    }

    private static func buildHeroBanner(from shelves: [(title: String, items: [ShelfItem])]) -> [HeroBannerItem] {
        guard let first = shelves.first else { return [] }
        return first.items.prefix(5).map { item in
            HeroBannerItem(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
        }
    }



    func isGarbageCategory(_ name: String) -> Bool {
        !CategoryNormalizer.isPrimaryCategoryVisible(
            name,
            provider: .xtream,
            contentType: .movie
        )
    }
}
