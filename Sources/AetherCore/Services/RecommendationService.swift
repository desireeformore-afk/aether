import Foundation
import Combine

/// Service for generating channel recommendations based on viewing history
@MainActor
public final class RecommendationService: ObservableObject {
    @Published public private(set) var recommendations: [ChannelRecommendation] = []
    @Published public private(set) var isGenerating: Bool = false

    public struct ChannelRecommendation: Identifiable, Codable {
        public let id: UUID
        public let channelName: String
        public let score: Double
        public let reason: RecommendationReason
        public let timestamp: Date

        public init(id: UUID = UUID(), channelName: String, score: Double, reason: RecommendationReason, timestamp: Date = Date()) {
            self.id = id
            self.channelName = channelName
            self.score = score
            self.reason = reason
            self.timestamp = timestamp
        }
    }

    public enum RecommendationReason: String, Codable {
        case similarToFavorites = "Similar to your favorites"
        case popularInCategory = "Popular in category"
        case watchedSimilarChannels = "Based on similar channels"
        case timeOfDay = "Popular at this time"
        case trending = "Trending now"
        case newContent = "New content available"
        case unwatched = "You haven't watched this yet"
    }

    private let analyticsService: AnalyticsService
    private var cancellables = Set<AnyCancellable>()

    public init(analyticsService: AnalyticsService) {
        self.analyticsService = analyticsService
        setupObservers()
    }

    private func setupObservers() {
        // Regenerate recommendations when analytics change
        analyticsService.$channelStats
            .debounce(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.generateRecommendations()
                }
            }
            .store(in: &cancellables)
    }

    public func generateRecommendations(for channels: [Channel] = []) async {
        isGenerating = true
        defer { isGenerating = false }

        var newRecommendations: [ChannelRecommendation] = []

        // Get viewing statistics
        let channelStats = analyticsService.channelStats
        let viewingStats = analyticsService.viewingStats

        // 1. Recommend similar channels to favorites
        if !viewingStats.favoriteChannels.isEmpty {
            let similarChannels = findSimilarChannels(to: viewingStats.favoriteChannels, in: channels)
            for channel in similarChannels.prefix(5) {
                let recommendation = ChannelRecommendation(
                    channelName: channel.name,
                    score: 0.9,
                    reason: .similarToFavorites
                )
                newRecommendations.append(recommendation)
            }
        }

        // 2. Recommend popular channels in most watched category
        if let category = viewingStats.mostWatchedCategory {
            let categoryChannels = channels.filter { $0.groupTitle == category }
            let unwatchedInCategory = categoryChannels.filter { channel in
                !channelStats.contains { $0.channelName == channel.name }
            }
            for channel in unwatchedInCategory.prefix(3) {
                let recommendation = ChannelRecommendation(
                    channelName: channel.name,
                    score: 0.8,
                    reason: .popularInCategory
                )
                newRecommendations.append(recommendation)
            }
        }

        // 3. Recommend based on time of day
        if let peakHour = viewingStats.peakViewingHour {
            let currentHour = Calendar.current.component(.hour, from: Date())
            if abs(currentHour - peakHour) <= 2 {
                // Recommend channels watched during peak hours
                let peakChannels = findChannelsWatchedDuringHour(peakHour, in: channelStats)
                for channelName in peakChannels.prefix(3) {
                    let recommendation = ChannelRecommendation(
                        channelName: channelName,
                        score: 0.7,
                        reason: .timeOfDay
                    )
                    newRecommendations.append(recommendation)
                }
            }
        }

        // 4. Recommend unwatched channels
        let watchedChannelNames = Set(channelStats.map { $0.channelName })
        let unwatchedChannels = channels.filter { !watchedChannelNames.contains($0.name) }
        for channel in unwatchedChannels.prefix(5) {
            let recommendation = ChannelRecommendation(
                channelName: channel.name,
                score: 0.5,
                reason: .unwatched
            )
            newRecommendations.append(recommendation)
        }

        // Sort by score and remove duplicates
        let uniqueRecommendations = Dictionary(grouping: newRecommendations, by: { $0.channelName })
            .compactMap { $0.value.max(by: { $0.score < $1.score }) }
            .sorted { $0.score > $1.score }

        recommendations = Array(uniqueRecommendations.prefix(10))
        saveRecommendations()
    }

    private func findSimilarChannels(to favorites: [String], in channels: [Channel]) -> [Channel] {
        // Simple similarity: same category as favorites
        let favoriteCategories = channels
            .filter { favorites.contains($0.name) }
            .compactMap { $0.groupTitle }

        return channels.filter { channel in
            !favorites.contains(channel.name) &&
            favoriteCategories.contains(channel.groupTitle ?? "")
        }
    }

    private func findChannelsWatchedDuringHour(_ hour: Int, in stats: [AnalyticsService.ChannelStatistics]) -> [String] {
        // Return channels with high watch counts (proxy for peak hour channels)
        return stats
            .sorted { $0.watchCount > $1.watchCount }
            .prefix(5)
            .map { $0.channelName }
    }

    public func dismissRecommendation(_ id: UUID) {
        recommendations.removeAll { $0.id == id }
        saveRecommendations()
    }

    public func clearRecommendations() {
        recommendations.removeAll()
        saveRecommendations()
    }

    // MARK: - Persistence

    private func saveRecommendations() {
        guard let data = try? JSONEncoder().encode(recommendations) else { return }
        UserDefaults.standard.set(data, forKey: "recommendations")
    }

    private func loadRecommendations() {
        guard let data = UserDefaults.standard.data(forKey: "recommendations"),
              let loaded = try? JSONDecoder().decode([ChannelRecommendation].self, from: data) else {
            return
        }
        recommendations = loaded
    }

    // MARK: - Export

    public func exportRecommendations(to url: URL) {
        guard let data = try? JSONEncoder().encode(recommendations) else { return }
        try? data.write(to: url)
    }
}
