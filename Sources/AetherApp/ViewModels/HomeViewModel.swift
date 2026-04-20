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
    @Published var errorMessage: String? = nil

    // Static cache — shared across views, survives navigation
    static var cachedVODShelves: [(title: String, items: [ShelfItem])]? = nil
    static var cachedSeriesShelves: [(title: String, items: [ShelfItem])]? = nil
    static var cachedLive: [ShelfItem]? = nil

    private var service: XstreamService?
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    var sharedService: XstreamService? { service }

    func loadIfNeeded() {
        guard !hasLoaded, let svc = service else { return }
        hasLoaded = true
        loadTask = Task { await performLoad(svc) }
    }

    func load(credentials: XstreamCredentials) {
        if service == nil {
            service = XstreamService(credentials: credentials)
        }
        // Restore from cache if already loaded
        if hasLoaded {
            if let cached = Self.cachedVODShelves, !shelves.isEmpty { return }
            if let cached = Self.cachedVODShelves {
                shelves = cached
                heroBannerItems = Self.buildHeroBanner(from: cached)
                isPhase1Loaded = true
            }
            if let cached = Self.cachedSeriesShelves { seriesShelves = cached }
            if let cached = Self.cachedLive { liveItems = cached }
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
        heroBannerItems = []
        shelves = []
        seriesShelves = []
        liveItems = []
        isPhase1Loaded = false
        isFullyLoaded = false
        load(credentials: credentials)
    }

    private func performLoad(_ svc: XstreamService) async {
        // Phase 1: Load VOD categories only (~38KB), pick best 8, signal UI immediately
        let allCats = (try? await svc.vodCategories()) ?? []
        let filtered = allCats
            .filter { !isGarbageCategory($0.name) }
            .sorted { $0.name < $1.name }
        let top8 = Array(filtered.prefix(8))

        // Load first 3 categories concurrently for the hero banner + initial shelves
        if !top8.isEmpty {
            let cats3 = Array(top8.prefix(3))
            let r0 = await loadVODShelf(svc: svc, cat: cats3[0])
            let r1 = cats3.count > 1 ? await loadVODShelf(svc: svc, cat: cats3[1]) : nil
            let r2 = cats3.count > 2 ? await loadVODShelf(svc: svc, cat: cats3[2]) : nil
            var initialShelves: [(title: String, items: [ShelfItem])] = []
            if let r = r0 { initialShelves.append(r) }
            if let r = r1 { initialShelves.append(r) }
            if let r = r2 { initialShelves.append(r) }
            shelves = initialShelves
            heroBannerItems = Self.buildHeroBanner(from: initialShelves)
        }
        isPhase1Loaded = true

        // Phase 2: Load remaining categories sequentially (avoids actor isolation issues)
        var allShelves = shelves
        for cat in top8.dropFirst(3) {
            if let shelf = await loadVODShelf(svc: svc, cat: cat) {
                allShelves.append(shelf)
                shelves = allShelves
            }
        }
        Self.cachedVODShelves = allShelves
        heroBannerItems = Self.buildHeroBanner(from: allShelves)

        // Load series categories
        let allSeriesCats = (try? await svc.seriesCategories()) ?? []
        let cleanSeriesCats = allSeriesCats
            .filter { !isGarbageCategory($0.name) }
            .sorted { $0.name < $1.name }
        var seriesResults: [(title: String, items: [ShelfItem])] = []
        for cat in cleanSeriesCats.prefix(4) {
            if let shelf = await loadSeriesShelf(svc: svc, cat: cat) {
                seriesResults.append(shelf)
                seriesShelves = seriesResults
            }
        }
        Self.cachedSeriesShelves = seriesResults

        // Load live channels
        let liveStreams = (try? await svc.liveStreams()) ?? []
        let liveShelfItems = liveStreams.prefix(30).map { stream in
            ShelfItem(id: "\(stream.id)", title: stream.name, imageURL: stream.streamIcon, onTap: {})
        }
        liveItems = Array(liveShelfItems)
        Self.cachedLive = Array(liveShelfItems)

        isFullyLoaded = true
    }

    private func loadVODShelf(svc: XstreamService, cat: XstreamCategory) async -> (title: String, items: [ShelfItem])? {
        guard let streams = try? await svc.vodStreams(categoryID: cat.id), !streams.isEmpty else { return nil }
        let cleanName = cleanCategoryName(cat.name)
        let items = streams.prefix(20).map { vod in
            ShelfItem(id: "\(vod.id)", title: vod.name, imageURL: vod.streamIcon, onTap: {})
        }
        return (cleanName, Array(items))
    }

    private func loadSeriesShelf(svc: XstreamService, cat: XstreamSeriesCategory) async -> (title: String, items: [ShelfItem])? {
        guard let series = try? await svc.seriesList(categoryID: cat.id), !series.isEmpty else { return nil }
        let cleanName = cleanCategoryName(cat.name)
        let items = series.prefix(20).map { s in
            ShelfItem(id: "\(s.id)", title: s.name, imageURL: s.cover, onTap: {})
        }
        return (cleanName, Array(items))
    }

    private static func buildHeroBanner(from shelves: [(title: String, items: [ShelfItem])]) -> [HeroBannerItem] {
        guard let first = shelves.first else { return [] }
        return first.items.prefix(5).map { item in
            HeroBannerItem(title: item.title, imageURL: item.imageURL, onTap: item.onTap)
        }
    }

    func cleanCategoryName(_ name: String) -> String {
        var clean = name
        if let range = clean.range(of: " - ") {
            clean = String(clean[range.upperBound...])
        }
        return clean.trimmingCharacters(in: .whitespaces)
    }

    func isGarbageCategory(_ name: String) -> Bool {
        if name.isEmpty { return true }
        if name.unicodeScalars.contains(where: { $0.value > 0x0600 && $0.value < 0x06FF }) { return true }
        let garbage = ["netflix", "amazon", "apple tv", "disney", "hbo", "premium", "adult", "xxx", "18+"]
        let lower = name.lowercased()
        return garbage.contains(where: { lower.contains($0) })
    }
}
