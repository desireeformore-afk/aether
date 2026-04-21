import SwiftUI
import SwiftData
import AetherCore

// MARK: - WatchHistoryShelf

/// Horizontal "Continue Watching" + "Recently Watched" shelves.
/// Drop this into HomeView above all other shelves.
struct WatchHistoryShelf: View {
    @Query(sort: \WatchHistoryRecord.watchedAt, order: .reverse)
    private var allHistory: [WatchHistoryRecord]

    @Bindable var player: PlayerCore

    private var continueWatching: [WatchHistoryRecord] {
        allHistory.filter { $0.isContinueWatching }.prefix(10).map { $0 }
    }

    private var recentlyWatched: [WatchHistoryRecord] {
        Array(allHistory.prefix(10))
    }

    var body: some View {
        if !allHistory.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if !continueWatching.isEmpty {
                    Text("Kontynuuj oglądanie")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(continueWatching, id: \.persistentModelID) { record in
                                ContinueWatchingCard(record: record, player: player)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                Text("Ostatnio oglądane")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(recentlyWatched, id: \.persistentModelID) { record in
                            RecentlyWatchedCard(record: record, player: player)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }
}

// MARK: - ContinueWatchingCard

struct ContinueWatchingCard: View {
    let record: WatchHistoryRecord
    @Bindable var player: PlayerCore
    @State private var isHovered = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: resumePlayback) {
                ZStack(alignment: .bottomLeading) {
                    posterImage(url: record.logoURLString.flatMap { URL(string: $0) })
                        .frame(width: 160, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Gradient + progress bar
                    VStack(spacing: 0) {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 60)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(height: 3)
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: geo.size.width * record.progressFraction, height: 3)
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .frame(width: 160, height: 240)

                    if isHovered {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.4))
                            .frame(width: 160, height: 240)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                            .frame(width: 160, height: 240)
                    }
                }
                .contentShape(Rectangle())
                .scaleEffect(isHovered ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("Usuń z historii", role: .destructive) {
                    modelContext.delete(record)
                    try? modelContext.save()
                }
            }

            Text(record.channelName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            if record.totalDurationSeconds > 0 {
                let remaining = record.totalDurationSeconds - record.watchedSecondsDouble
                Text(formatTime(remaining) + " pozostało")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func resumePlayback() {
        guard let channel = record.toChannel() else { return }
        player.play(channel)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        if mins >= 60 { return "\(mins / 60)g \(mins % 60)m" }
        return "\(mins)m"
    }
}

// MARK: - RecentlyWatchedCard

struct RecentlyWatchedCard: View {
    let record: WatchHistoryRecord
    @Bindable var player: PlayerCore
    @State private var isHovered = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                posterImage(url: record.logoURLString.flatMap { URL(string: $0) })
                    .frame(width: 130, height: 195)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.4))
                        .frame(width: 130, height: 195)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                }

                if record.isFinished {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.green)
                                .padding(6)
                        }
                        Spacer()
                    }
                    .frame(width: 130, height: 195)
                }
            }
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
            .onTapGesture { resumePlayback() }
            .contextMenu {
                Button("Usuń z historii", role: .destructive) {
                    modelContext.delete(record)
                    try? modelContext.save()
                }
            }

            Text(record.channelName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 130, alignment: .leading)

            Text(record.watchedAt.relativeFormatted())
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func resumePlayback() {
        guard let channel = record.toChannel() else { return }
        player.play(channel)
    }
}

// MARK: - Poster helper

@ViewBuilder
private func posterImage(url: URL?) -> some View {
    AsyncImage(url: url) { phase in
        switch phase {
        case .success(let img):
            img.resizable().aspectRatio(contentMode: .fill)
        default:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.sRGB, red: 0.15, green: 0.15, blue: 0.18))
                .overlay(
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.3))
                )
        }
    }
}

// MARK: - Date extension

private extension Date {
    func relativeFormatted() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - WatchHistoryView (full browser sheet)

/// Full watch history browser — accessible from PlaylistSidebar "History" button.
struct WatchHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WatchHistoryRecord.watchedAt, order: .reverse) private var history: [WatchHistoryRecord]
    @Environment(PlayerCore.self) private var playerCore

    @State private var searchText = ""
    @State private var showClearConfirm = false

    private var filtered: [WatchHistoryRecord] {
        guard !searchText.isEmpty else { return history }
        return history.filter {
            $0.channelName.localizedCaseInsensitiveContains(searchText) ||
            $0.groupTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No History" : "No Results",
                        systemImage: searchText.isEmpty ? "clock" : "magnifyingglass",
                        description: Text(searchText.isEmpty
                            ? "Channels you watch will appear here."
                            : "No history matches \"\(searchText)\"."
                        )
                    )
                } else {
                    List {
                        ForEach(groupedByDay, id: \.day) { section in
                            Section(section.day) {
                                ForEach(section.records) { record in
                                    HistoryRow(record: record)
                                        .contentShape(Rectangle())
                                        .onTapGesture { playAndDismiss(record) }
                                }
                                .onDelete { offsets in
                                    deleteRecords(section.records, at: offsets)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Watch History")
            .searchable(text: $searchText, prompt: "Search history")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(history.isEmpty)
                    .help("Delete entire watch history")
                }
            }
            .confirmationDialog(
                "Clear all watch history?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) { clearAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    private struct DaySection: Identifiable {
        let id = UUID()
        let day: String
        let records: [WatchHistoryRecord]
    }

    private var groupedByDay: [DaySection] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let grouped = Dictionary(grouping: filtered) {
            formatter.string(from: $0.watchedAt)
        }
        return grouped
            .sorted { a, b in
                let dateA = a.value.first?.watchedAt ?? .distantPast
                let dateB = b.value.first?.watchedAt ?? .distantPast
                return dateA > dateB
            }
            .map { DaySection(day: $0.key, records: $0.value) }
    }

    private func playAndDismiss(_ record: WatchHistoryRecord) {
        guard let channel = record.toChannel() else { return }
        playerCore.play(channel)
        dismiss()
    }

    private func deleteRecords(_ records: [WatchHistoryRecord], at offsets: IndexSet) {
        for idx in offsets {
            modelContext.delete(records[idx])
        }
    }

    private func clearAll() {
        for record in history {
            modelContext.delete(record)
        }
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let record: WatchHistoryRecord

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            ChannelLogoView(url: record.logoURLString.flatMap { URL(string: $0) })
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.channelName)
                    .font(.aetherBody)
                    .foregroundStyle(Color.aetherText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(record.groupTitle)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                    if record.durationSeconds > 0 {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(formatDuration(record.durationSeconds))
                            .font(.aetherCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(Self.timeFormatter.string(from: record.watchedAt))
                .font(.aetherCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rem = m % 60
        return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
    }
}
