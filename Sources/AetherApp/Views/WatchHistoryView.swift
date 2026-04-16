import SwiftUI
import SwiftData
import AetherCore

/// Full watch history browser — accessible from PlaylistSidebar "History" button.
struct WatchHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WatchHistoryRecord.watchedAt, order: .reverse) private var history: [WatchHistoryRecord]
    @EnvironmentObject private var playerCore: PlayerCore

    @State private var searchText = ""
    @State private var showClearConfirm = false

    // MARK: - Filtered history

    private var filtered: [WatchHistoryRecord] {
        guard !searchText.isEmpty else { return history }
        return history.filter {
            $0.channelName.localizedCaseInsensitiveContains(searchText) ||
            $0.groupTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Body

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

    // MARK: - Grouping by day

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
                // Sort by the first record's date descending
                let dateA = a.value.first?.watchedAt ?? .distantPast
                let dateB = b.value.first?.watchedAt ?? .distantPast
                return dateA > dateB
            }
            .map { DaySection(day: $0.key, records: $0.value) }
    }

    // MARK: - Actions

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
