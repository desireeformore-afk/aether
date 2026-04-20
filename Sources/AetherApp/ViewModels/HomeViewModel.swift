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

    // Priority-sorted VOD shelves exposed to VODBrowserView
    @Published var streamingServiceShelves: [(title: String, icon: String, items: [ShelfItem])] = []
    @Published var genreShelves: [(title: String, items: [ShelfItem])] = []

    // Static cache — shared across views, survives navigation
    static var cachedVODShelves: [(title: String, items: [ShelfItem])]? = nil
    static var cachedSeriesShelves: [(title: String, items: [ShelfItem])]? = nil
    static var cachedLive: [ShelfItem]? = nil
    static var cachedAllVODs: [XstreamVOD]? = nil
    static var cachedAllSeries: [XstreamSeries]? = nil

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
        let allCats = (try? await svc.vodCategories()) ?? []
        let filtered = allCats
            .filter { !isGarbageCategory($0.name) }
            .sorted { $0.name < $1.name }

        // Load up to 16 VOD shelves total
        let top16 = Array(filtered.prefix(16))

        // Phase 1: first 3 shelves for hero banner + initial display
        if !top16.isEmpty {
            let cats3 = Array(top16.prefix(3))
            let r0 = await loadVODShelf(svc: svc, cat: cats3[0])
            let r1 = cats3.count > 1 ? await loadVODShelf(svc: svc, cat: cats3[1]) : nil
            let r2 = cats3.count > 2 ? await loadVODShelf(svc: svc, cat: cats3[2]) : nil
            var initialShelves: [(title: String, items: [ShelfItem])] = []
            if let r = r0 { initialShelves.append(r) }
            if let r = r1 { initialShelves.append(r) }
            if let r = r2 { initialShelves.append(r) }
            shelves = initialShelves
            heroBannerItems = Self.buildHeroBanner(from: initialShelves)
            rebuildPriorityShelves(from: initialShelves)
            allVODs = initialShelves.flatMap { $0.items.compactMap { $0.vod } }
        }
        isPhase1Loaded = true

        // Phase 2: remaining shelves, progressive rendering
        var allShelves = shelves
        var collectedVODs: [XstreamVOD] = allVODs
        for cat in top16.dropFirst(3) {
            if let shelf = await loadVODShelf(svc: svc, cat: cat) {
                allShelves.append(shelf)
                shelves = allShelves
                rebuildPriorityShelves(from: allShelves)
                collectedVODs.append(contentsOf: shelf.items.compactMap { $0.vod })
                allVODs = collectedVODs
            }
        }
        Self.cachedVODShelves = allShelves
        Self.cachedAllVODs = collectedVODs
        heroBannerItems = Self.buildHeroBanner(from: allShelves)

        // Load series categories (top 8)
        let allSeriesCats = (try? await svc.seriesCategories()) ?? []
        let cleanSeriesCats = allSeriesCats
            .filter { !isGarbageCategory($0.name) }
            .sorted { $0.name < $1.name }
        var seriesResults: [(title: String, items: [ShelfItem])] = []
        var collectedSeries: [XstreamSeries] = []
        for cat in cleanSeriesCats.prefix(8) {
            if let shelf = await loadSeriesShelf(svc: svc, cat: cat) {
                seriesResults.append(shelf)
                seriesShelves = seriesResults
                collectedSeries.append(contentsOf: shelf.items.compactMap { $0.series })
                allSeries = collectedSeries
            }
        }
        Self.cachedSeriesShelves = seriesResults
        Self.cachedAllSeries = collectedSeries

        // Load live channels (first 20)
        let liveStreams = (try? await svc.liveStreams()) ?? []
        let liveShelfItems = liveStreams.prefix(20).map { stream in
            ShelfItem(id: "\(stream.id)", title: stream.name, imageURL: stream.streamIcon, onTap: {})
        }
        liveItems = Array(liveShelfItems)
        Self.cachedLive = Array(liveShelfItems)

        isFullyLoaded = true
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
        var streaming: [(title: String, icon: String, items: [ShelfItem])] = []
        var genre: [(title: String, items: [ShelfItem])] = []
        var used = Set<String>()

        for shelf in shelves {
            let lower = shelf.title.lowercased()
            if let svc = Self.streamingServices.first(where: { $0.keywords.contains(where: { lower.contains($0) }) }) {
                if !used.contains(svc.label) {
                    streaming.append((title: svc.label, icon: svc.icon, items: shelf.items))
                    used.insert(svc.label)
                }
            } else if let g = Self.genreKeywords.first(where: { $0.keywords.contains(where: { lower.contains($0) }) }) {
                if !used.contains(g.label) {
                    genre.append((title: g.label, items: shelf.items))
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
            ShelfItem(id: "\(vod.id)", title: vod.name, imageURL: vod.streamIcon, vod: vod, onTap: {})
        }
        return (cleanName, Array(items))
    }

    private func loadSeriesShelf(svc: XstreamService, cat: XstreamSeriesCategory) async -> (title: String, items: [ShelfItem])? {
        guard let series = try? await svc.seriesList(categoryID: cat.id), !series.isEmpty else { return nil }
        let cleanName = cleanCategoryName(cat.name)
        let items = series.prefix(20).map { s in
            ShelfItem(id: "\(s.id)", title: s.name, imageURL: s.cover, series: s, onTap: {})
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
        if upper.hasPrefix("TR") || upper.contains("TUR") {
            clean = "🇹🇷 \(clean)"
        } else if upper.hasPrefix("PL") || upper.contains(" PL ") {
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

