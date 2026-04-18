import Foundation
import Combine

/// Service for tracking and analyzing user viewing statistics
@MainActor
@Observable
public final class AnalyticsService {
    @Published public private(set) var viewingStats: ViewingStatistics
    @Published public private(set) var channelStats: [ChannelStatistics] = []
    @Published public private(set) var dailyStats: [DailyStatistics] = []

    public struct ViewingStatistics: Codable {
        public var totalWatchTime: TimeInterval = 0
        public var totalChannelSwitches: Int = 0
        public var totalSessions: Int = 0
        public var averageSessionDuration: TimeInterval = 0
        public var favoriteChannels: [String] = []
        public var mostWatchedCategory: String?
        public var peakViewingHour: Int?

        public init() {}
    }

    public struct ChannelStatistics: Codable, Identifiable {
        public let id: UUID
        public let channelName: String
        public var watchCount: Int
        public var totalWatchTime: TimeInterval
        public var lastWatched: Date?
        public var averageSessionDuration: TimeInterval

        public init(id: UUID = UUID(), channelName: String, watchCount: Int = 0, totalWatchTime: TimeInterval = 0, lastWatched: Date? = nil, averageSessionDuration: TimeInterval = 0) {
            self.id = id
            self.channelName = channelName
            self.watchCount = watchCount
            self.totalWatchTime = totalWatchTime
            self.lastWatched = lastWatched
            self.averageSessionDuration = averageSessionDuration
        }
    }

    public struct DailyStatistics: Codable, Identifiable {
        public let id: UUID
        public let date: Date
        public var watchTime: TimeInterval
        public var sessionCount: Int
        public var channelSwitches: Int
        public var topChannels: [String]

        public init(id: UUID = UUID(), date: Date, watchTime: TimeInterval = 0, sessionCount: Int = 0, channelSwitches: Int = 0, topChannels: [String] = []) {
            self.id = id
            self.date = date
            self.watchTime = watchTime
            self.sessionCount = sessionCount
            self.channelSwitches = channelSwitches
            self.topChannels = topChannels
        }
    }

    public struct WatchSession: Codable {
        public let channelName: String
        public let startTime: Date
        public let duration: TimeInterval
        public let category: String?

        public init(channelName: String, startTime: Date, duration: TimeInterval, category: String? = nil) {
            self.channelName = channelName
            self.startTime = startTime
            self.duration = duration
            self.category = category
        }
    }

    private var sessions: [WatchSession] = []
    private let maxSessionsToKeep = 1000

    public init() {
        self.viewingStats = ViewingStatistics()
        loadStatistics()
    }

    public func recordWatchSession(channelName: String, startTime: Date, duration: TimeInterval, category: String? = nil) {
        let session = WatchSession(
            channelName: channelName,
            startTime: startTime,
            duration: duration,
            category: category
        )

        sessions.append(session)

        // Keep only recent sessions
        if sessions.count > maxSessionsToKeep {
            sessions.removeFirst(sessions.count - maxSessionsToKeep)
        }

        // Update statistics
        updateStatistics(with: session)
        saveStatistics()
    }

    private func updateStatistics(with session: WatchSession) {
        // Update overall stats
        viewingStats.totalWatchTime += session.duration
        viewingStats.totalSessions += 1
        viewingStats.averageSessionDuration = viewingStats.totalWatchTime / Double(viewingStats.totalSessions)

        // Update channel stats
        if let index = channelStats.firstIndex(where: { $0.channelName == session.channelName }) {
            channelStats[index].watchCount += 1
            channelStats[index].totalWatchTime += session.duration
            channelStats[index].lastWatched = session.startTime
            channelStats[index].averageSessionDuration = channelStats[index].totalWatchTime / Double(channelStats[index].watchCount)
        } else {
            let newStat = ChannelStatistics(
                channelName: session.channelName,
                watchCount: 1,
                totalWatchTime: session.duration,
                lastWatched: session.startTime,
                averageSessionDuration: session.duration
            )
            channelStats.append(newStat)
        }

        // Update daily stats
        let calendar = Calendar.current
        let sessionDate = calendar.startOfDay(for: session.startTime)

        if let index = dailyStats.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: sessionDate) }) {
            dailyStats[index].watchTime += session.duration
            dailyStats[index].sessionCount += 1
            if !dailyStats[index].topChannels.contains(session.channelName) {
                dailyStats[index].topChannels.append(session.channelName)
            }
        } else {
            let newDaily = DailyStatistics(
                date: sessionDate,
                watchTime: session.duration,
                sessionCount: 1,
                channelSwitches: 0,
                topChannels: [session.channelName]
            )
            dailyStats.append(newDaily)
        }

        // Update derived stats
        updateDerivedStatistics()
    }

    private func updateDerivedStatistics() {
        // Find favorite channels (top 5 by watch time)
        let sortedChannels = channelStats.sorted { $0.totalWatchTime > $1.totalWatchTime }
        viewingStats.favoriteChannels = Array(sortedChannels.prefix(5).map { $0.channelName })

        // Find peak viewing hour
        let hourCounts = sessions.reduce(into: [Int: Int]()) { counts, session in
            let hour = Calendar.current.component(.hour, from: session.startTime)
            counts[hour, default: 0] += 1
        }
        viewingStats.peakViewingHour = hourCounts.max(by: { $0.value < $1.value })?.key
    }

    public func recordChannelSwitch() {
        viewingStats.totalChannelSwitches += 1

        // Update today's daily stats
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let index = dailyStats.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            dailyStats[index].channelSwitches += 1
        }

        saveStatistics()
    }

    public func getTopChannels(limit: Int = 10) -> [ChannelStatistics] {
        return Array(channelStats.sorted { $0.totalWatchTime > $1.totalWatchTime }.prefix(limit))
    }

    public func getRecentSessions(limit: Int = 20) -> [WatchSession] {
        return Array(sessions.suffix(limit).reversed())
    }

    public func getWatchTimeForPeriod(days: Int) -> TimeInterval {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        return sessions
            .filter { $0.startTime >= startDate }
            .reduce(0) { $0 + $1.duration }
    }

    public func getSessionCountForPeriod(days: Int) -> Int {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        return sessions.filter { $0.startTime >= startDate }.count
    }

    public func getDailyStatsForPeriod(days: Int) -> [DailyStatistics] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        return dailyStats
            .filter { $0.date >= startDate }
            .sorted { $0.date < $1.date }
    }

    public func clearStatistics() {
        viewingStats = ViewingStatistics()
        channelStats.removeAll()
        dailyStats.removeAll()
        sessions.removeAll()
        saveStatistics()
    }

    public func exportStatistics() -> Data? {
        let export = StatisticsExport(
            viewingStats: viewingStats,
            channelStats: channelStats,
            dailyStats: dailyStats,
            sessions: sessions
        )

        return try? JSONEncoder().encode(export)
    }

    private struct StatisticsExport: Codable {
        let viewingStats: ViewingStatistics
        let channelStats: [ChannelStatistics]
        let dailyStats: [DailyStatistics]
        let sessions: [WatchSession]
    }

    private func saveStatistics() {
        let data: [String: Any] = [
            "viewingStats": (try? JSONEncoder().encode(viewingStats)) ?? Data(),
            "channelStats": (try? JSONEncoder().encode(channelStats)) ?? Data(),
            "dailyStats": (try? JSONEncoder().encode(dailyStats)) ?? Data(),
            "sessions": (try? JSONEncoder().encode(sessions)) ?? Data()
        ]

        for (key, value) in data {
            UserDefaults.standard.set(value, forKey: "analytics_\(key)")
        }
    }

    private func loadStatistics() {
        if let data = UserDefaults.standard.data(forKey: "analytics_viewingStats"),
           let stats = try? JSONDecoder().decode(ViewingStatistics.self, from: data) {
            viewingStats = stats
        }

        if let data = UserDefaults.standard.data(forKey: "analytics_channelStats"),
           let stats = try? JSONDecoder().decode([ChannelStatistics].self, from: data) {
            channelStats = stats
        }

        if let data = UserDefaults.standard.data(forKey: "analytics_dailyStats"),
           let stats = try? JSONDecoder().decode([DailyStatistics].self, from: data) {
            dailyStats = stats
        }

        if let data = UserDefaults.standard.data(forKey: "analytics_sessions"),
           let loadedSessions = try? JSONDecoder().decode([WatchSession].self, from: data) {
            sessions = loadedSessions
        }
    }
}
