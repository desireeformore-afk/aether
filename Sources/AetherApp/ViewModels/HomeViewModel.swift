import SwiftUI
import AetherCore

private struct SeriesShelfPayload: Sendable {
    let title: String
    let series: [XstreamSeries]
}

private struct VODShelfPayload: Sendable {
    let allShelves: [(title: String, items: [VODShelfItemPayload])]
    let hubToShelves: [BrandHub: [String: [String: VODShelfItemPayload]]]
}

private struct VODShelfItemPayload: Identifiable, Sendable {
    let id: String
    let title: String
    let imageURL: String?
    let vod: XstreamVOD
    var tags: Set<VODTag>
    var alternateVODs: [XstreamVOD]

    func makeShelfItem() -> ShelfItem {
        ShelfItem(
            id: id,
            title: title,
            imageURL: imageURL,
            vod: vod,
            tags: tags,
            alternateVODs: alternateVODs,
            onTap: {}
        )
    }
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
    @Published var catalogSnapshot: CatalogSnapshot = .empty
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
    static var cachedCatalogSnapshots: [String: CatalogSnapshot] = [:]

    // MARK: - Disk cache keys
    private static let baseDiskCacheKey = "homevm_shelves_v1"
    private static let baseDiskCacheAgeKey = "homevm_cache_age_v1"
    private static let maxCacheAge: TimeInterval = 3600 // 1 hour

    private var service: XstreamService?
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?
    private var activeCacheKey: String?
    private let catalogIndex = CatalogIndex()

    @AppStorage("preferredLanguage") var preferredLanguage: String = "pl"
    @AppStorage("preferredCountry") var preferredCountry: String = "PL"

    var sharedService: XstreamService? { service }

    func searchCatalog(query: String, limit: Int = 30) async -> CatalogSearchResults {
        await catalogIndex.search(query: query, limit: limit)
    }

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

        // INSTANT: show memory/disk cache before even starting network load.
        if shelves.isEmpty {
            if let cached = Self.cachedVODShelves[cacheKey] {
                shelves = cached
                heroBannerItems = Self.buildHeroBanner(from: cached)
                isPhase1Loaded = true
            } else if let diskCached = Self.loadFromDiskCache(cacheKey: cacheKey) {
                shelves = diskCached
                heroBannerItems = Self.buildHeroBanner(from: diskCached)
                isPhase1Loaded = true
            }
        }
        if brandHubs.isEmpty, let cachedHubs = Self.cachedBrandHubs[cacheKey] { brandHubs = cachedHubs }
        if seriesShelves.isEmpty, let cached = Self.cachedSeriesShelves[cacheKey] { seriesShelves = cached }
        if liveItems.isEmpty, let cached = Self.cachedLive[cacheKey] { liveItems = cached }
        if allVODs.isEmpty, let cached = Self.cachedAllVODs[cacheKey] { allVODs = cached }
        if allSeries.isEmpty, let cached = Self.cachedAllSeries[cacheKey] { allSeries = cached }
        if catalogSnapshot.isEmpty, let cached = Self.cachedCatalogSnapshots[cacheKey] {
            catalogSnapshot = cached
            Task { await catalogIndex.update(vods: allVODs, series: allSeries) }
        }
        if catalogSnapshot.isEmpty, !allVODs.isEmpty || !allSeries.isEmpty {
            let cachedVODs = allVODs
            let cachedSeries = allSeries
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snapshot = await self.catalogIndex.update(vods: cachedVODs, series: cachedSeries)
                guard self.activeCacheKey == cacheKey else { return }
                self.catalogSnapshot = snapshot
                Self.cachedCatalogSnapshots[cacheKey] = snapshot
            }
        }
        if Self.cachedAllVODs[cacheKey] != nil,
           Self.cachedSeriesShelves[cacheKey] != nil,
           Self.cachedLive[cacheKey] != nil {
            isPhase1Loaded = true
            isFullyLoaded = true
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
            if let cached = Self.cachedCatalogSnapshots[cacheKey] {
                catalogSnapshot = cached
                Task { await catalogIndex.update(vods: allVODs, series: allSeries) }
            }
            if Self.cachedAllVODs[cacheKey] != nil,
               Self.cachedSeriesShelves[cacheKey] != nil,
               Self.cachedLive[cacheKey] != nil {
                isFullyLoaded = true
            }
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
        Self.cachedCatalogSnapshots.removeValue(forKey: cacheKey)
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
            if shelves.isEmpty {
                let previewStreams = try await svc.vodStreamsFast()
                guard isActive(cacheKey) else { return }

                let previewPayload = Self.buildVODShelves(from: previewStreams)
                if previewPayload.allShelves.isEmpty {
                    self.errorMessage = "Brak dostępnych filmów."
                } else {
                    applyVODShelfPayload(
                        previewPayload,
                        allStreams: previewStreams,
                        cacheKey: cacheKey,
                        cacheFullLibrary: false
                    )
                    await refreshCatalogSnapshot(vods: previewStreams, series: allSeries, cacheKey: cacheKey)
                }
            }

            isPhase1Loaded = true

            async let fullVODLoad: Void = loadFullVODLibraryInBackground(svc, cacheKey: cacheKey)
            async let seriesLoad: Void = loadSeriesInBackground(svc, cacheKey: cacheKey)
            async let liveLoad: Void = loadLiveInBackground(svc, cacheKey: cacheKey)
            _ = await (fullVODLoad, seriesLoad, liveLoad)
            guard isActive(cacheKey) else { return }

            isFullyLoaded = true
        } catch {
            guard isActive(cacheKey) else { return }
            self.error = error
            self.errorMessage = error.localizedDescription
            isPhase1Loaded = true
        }
    }

    nonisolated private static func buildVODShelves(from allStreams: [XstreamVOD]) -> VODShelfPayload {
        // hub -> shelfName -> normalizedTitle -> Item
        var hubToShelves: [BrandHub: [String: [String: VODShelfItemPayload]]] = [:]

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
                let item = VODShelfItemPayload(
                    id: "\(vod.id)",
                    title: cleanTitle,
                    imageURL: vod.streamIcon,
                    vod: vod,
                    tags: tags,
                    alternateVODs: [vod]
                )
                shelfDict[lowerTitle] = item
            }

            var shelvesForHub = hubToShelves[hub] ?? [:]
            shelvesForHub[shelfName] = shelfDict
            hubToShelves[hub] = shelvesForHub
        }

        var finalShelves: [(title: String, items: [VODShelfItemPayload])] = []
        for hub in BrandHub.allCases {
            guard let shelvesDict = hubToShelves[hub] else { continue }
            for shelfName in shelvesDict.keys.sorted() {
                let items = shelvesDict[shelfName]!.values.sorted { $0.title < $1.title }
                if !items.isEmpty {
                    finalShelves.append((title: shelfName, items: items))
                }
            }
        }

        return VODShelfPayload(allShelves: finalShelves, hubToShelves: hubToShelves)
    }

    private func applyVODShelfPayload(
        _ payload: VODShelfPayload,
        allStreams: [XstreamVOD],
        cacheKey: String,
        cacheFullLibrary: Bool
    ) {
        let topVODShelves = payload.allShelves.prefix(20).map { shelf in
            (title: shelf.title, items: shelf.items.map { $0.makeShelfItem() })
        }

        shelves = topVODShelves
        heroBannerItems = Self.buildHeroBanner(from: topVODShelves)
        brandHubs = Self.buildBrandHubs(from: payload.hubToShelves)
        allVODs = allStreams

        Self.cachedVODShelves[cacheKey] = topVODShelves
        Self.cachedBrandHubs[cacheKey] = brandHubs
        if cacheFullLibrary {
            Self.cachedAllVODs[cacheKey] = allStreams
        }
        Self.saveToDiskCache(topVODShelves, cacheKey: cacheKey)
    }

    private func refreshCatalogSnapshot(
        vods: [XstreamVOD],
        series: [XstreamSeries],
        cacheKey: String
    ) async {
        let snapshot = await catalogIndex.update(vods: vods, series: series)
        guard isActive(cacheKey) else { return }
        catalogSnapshot = snapshot
        Self.cachedCatalogSnapshots[cacheKey] = snapshot
    }

    private func loadFullVODLibraryInBackground(_ svc: XstreamService, cacheKey: String) async {
        do {
            let allStreams = try await svc.vodStreams(categoryID: nil)
            guard isActive(cacheKey) else { return }

            let fullPayload = await Task.detached(priority: .utility) {
                Self.buildVODShelves(from: allStreams)
            }.value
            guard !fullPayload.allShelves.isEmpty else { return }
            applyVODShelfPayload(
                fullPayload,
                allStreams: allStreams,
                cacheKey: cacheKey,
                cacheFullLibrary: true
            )
            await refreshCatalogSnapshot(vods: allStreams, series: allSeries, cacheKey: cacheKey)
        } catch {
            guard isActive(cacheKey) else { return }
            print("[HomeViewModel] Full VOD library load failed after phase 1: \(error.localizedDescription)")
        }
    }

    private static func buildBrandHubs(
        from hubToShelves: [BrandHub: [String: [String: VODShelfItemPayload]]]
    ) -> [(hub: BrandHub, shelves: [(title: String, items: [ShelfItem])])] {
        var grouped: [BrandHub: [(title: String, items: [ShelfItem])]] = [:]
        for hub in BrandHub.allCases {
            guard let shelvesDict = hubToShelves[hub] else { continue }
            var sortedHubShelves: [(title: String, items: [ShelfItem])] = []
            for shelfName in shelvesDict.keys.sorted() {
                guard let shelfItems = shelvesDict[shelfName] else { continue }
                let items = shelfItems.values
                    .sorted { $0.title < $1.title }
                    .map { $0.makeShelfItem() }
                if !items.isEmpty { sortedHubShelves.append((title: shelfName, items: items)) }
            }
            if !sortedHubShelves.isEmpty { grouped[hub] = sortedHubShelves }
        }
        return grouped.map { (hub: $0.key, shelves: $0.value) }
            .sorted { $0.hub.rawValue < $1.hub.rawValue }
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
        let payloads = await withTaskGroup(
            of: SeriesShelfPayload?.self,
            returning: [SeriesShelfPayload].self
        ) { group in
            for cat in clean.prefix(8) {
                group.addTask { await Self.loadSeriesShelfPayload(svc: svc, cat: cat) }
            }

            var payloads: [SeriesShelfPayload] = []
            for await payload in group {
                if let payload {
                    payloads.append(payload)
                }
            }
            return payloads
        }

        guard isActive(cacheKey) else { return }

        var results: [(title: String, items: [ShelfItem])] = []
        var collected: [XstreamSeries] = []
        for payload in payloads {
            let items = payload.series.map { series in
                ShelfItem(id: "\(series.id)", title: VODNormalizer.cleanVODTitle(series.name), imageURL: series.cover, series: series, onTap: {})
            }
            results.append((title: payload.title, items: items))
            collected.append(contentsOf: payload.series)
        }

        seriesShelves = results
        allSeries = collected
        Self.cachedSeriesShelves[cacheKey] = results
        Self.cachedAllSeries[cacheKey] = collected
        await refreshCatalogSnapshot(vods: allVODs, series: collected, cacheKey: cacheKey)
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
        catalogSnapshot = .empty
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
