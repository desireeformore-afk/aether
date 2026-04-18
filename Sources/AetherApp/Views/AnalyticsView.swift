import SwiftUI
import AetherCore
import Charts

struct AnalyticsView: View {
    @State var analyticsService: AnalyticsService

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Statistics & Analytics")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()

            // Tab Picker
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Channels").tag(1)
                Text("Timeline").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            // Content
            TabView(selection: $selectedTab) {
                overviewTab
                    .tag(0)

                channelsTab
                    .tag(1)

                timelineTab
                    .tag(2)
            }
            .tabViewStyle(.automatic)
        }
        .frame(width: 700, height: 600)
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Cards
                HStack(spacing: 16) {
                    StatCard(
                        title: "Total Watch Time",
                        value: formatDuration(analyticsService.viewingStats.totalWatchTime),
                        icon: "clock.fill",
                        color: .blue
                    )

                    StatCard(
                        title: "Total Sessions",
                        value: "\(analyticsService.viewingStats.totalSessions)",
                        icon: "play.circle.fill",
                        color: .green
                    )
                }

                HStack(spacing: 16) {
                    StatCard(
                        title: "Avg Session",
                        value: formatDuration(analyticsService.viewingStats.averageSessionDuration),
                        icon: "timer",
                        color: .orange
                    )

                    StatCard(
                        title: "Channel Switches",
                        value: "\(analyticsService.viewingStats.totalChannelSwitches)",
                        icon: "arrow.left.arrow.right",
                        color: .purple
                    )
                }

                // Favorite Channels
                VStack(alignment: .leading, spacing: 12) {
                    Text("Favorite Channels")
                        .font(.headline)

                    if analyticsService.viewingStats.favoriteChannels.isEmpty {
                        Text("No data yet")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(Array(analyticsService.viewingStats.favoriteChannels.enumerated()), id: \.offset) { index, channel in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text(channel)
                                    .font(.body)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                // Peak Viewing Hour
                if let peakHour = analyticsService.viewingStats.peakViewingHour {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Peak Viewing Hour")
                            .font(.headline)
                        Text("\(peakHour):00 - \(peakHour + 1):00")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Most Watched Category
                if let category = analyticsService.viewingStats.mostWatchedCategory {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Most Watched Category")
                            .font(.headline)
                        Text(category)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    // MARK: - Channels Tab

    private var channelsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                if analyticsService.channelStats.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No channel statistics yet")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ForEach(analyticsService.channelStats.sorted { $0.totalWatchTime > $1.totalWatchTime }) { stat in
                        ChannelStatRow(stat: stat)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Timeline Tab

    private var timelineTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                if analyticsService.dailyStats.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No daily statistics yet")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // Last 7 days chart
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Last 7 Days")
                            .font(.headline)

                        let last7Days = analyticsService.dailyStats
                            .sorted { $0.date > $1.date }
                            .prefix(7)
                            .reversed()

                        ForEach(Array(last7Days)) { daily in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(daily.date, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(formatDuration(daily.watchTime))
                                        .font(.body)
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                                Text("\(daily.sessionCount) sessions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ChannelStatRow: View {
    let stat: AnalyticsService.ChannelStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stat.channelName)
                    .font(.headline)
                Spacer()
                if let lastWatched = stat.lastWatched {
                    Text(lastWatched, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch Time")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatDuration(stat.totalWatchTime))
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(stat.watchCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Avg Duration")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatDuration(stat.averageSessionDuration))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
