import SwiftUI
import AetherCore

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var heroBannerVODs: [XstreamVOD] = []
    @Published var popularVODs: [XstreamVOD] = []
    @Published var recentVODs: [XstreamVOD] = []
    @Published var topSeries: [XstreamSeries] = []
    @Published var liveChannels: [Channel] = []
    @Published var isLoading = true
    @Published var loadingProgress: String = "Ładowanie..."

    private var service: XstreamService?
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    var sharedService: XstreamService? { service }

    func load(credentials: XstreamCredentials) {
        guard !hasLoaded else { return }
        hasLoaded = true
        let svc = XstreamService(credentials: credentials)
        service = svc
        loadTask = Task { await performLoad(svc) }
    }

    func forceReload(credentials: XstreamCredentials) {
        hasLoaded = false
        loadTask?.cancel()
        service = nil
        heroBannerVODs = []
        popularVODs = []
        recentVODs = []
        topSeries = []
        liveChannels = []
        isLoading = true
        load(credentials: credentials)
    }

    private func performLoad(_ svc: XstreamService) async {
        // Phase 1: fast — load a few categories only (~1–2 MB, ~1–2 s)
        loadingProgress = "Ładowanie filmów..."
        let fastVods = (try? await svc.vodStreamsFast()) ?? []
        let filtered = fastVods.filter { !$0.name.isEmpty && $0.streamIcon != nil }
        heroBannerVODs = Array(filtered.shuffled().prefix(5))
        popularVODs = Array(filtered.prefix(20))
        recentVODs = Array(filtered.suffix(20))
        isLoading = false

        // Phase 2: background — load everything for search
        loadingProgress = "Indeksowanie biblioteki..."
        async let allVods = (try? await svc.vodStreams()) ?? []
        async let allSeries = (try? await svc.seriesList()) ?? []
        async let channels = (try? await svc.channels()) ?? []

        let (vods, series, chans) = await (allVods, allSeries, channels)

        let cleanVods = vods.filter { !$0.name.isEmpty }
        if !cleanVods.isEmpty {
            heroBannerVODs = Array(cleanVods.shuffled().prefix(5))
            popularVODs = Array(cleanVods.prefix(20))
            recentVODs = Array(cleanVods.reversed().prefix(20))
        }
        topSeries = Array(series.prefix(20))
        liveChannels = Array(chans.prefix(50))
        loadingProgress = "Gotowe"
    }
}
