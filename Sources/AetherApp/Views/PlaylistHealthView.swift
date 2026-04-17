import SwiftUI
import AetherCore

// MARK: - PlaylistHealthView

/// Dashboard showing per-channel stream health after HEAD-ping validation.
struct PlaylistHealthView: View {
    let playlist: PlaylistRecord

    @State private var results: [ChannelCheckResult] = []
    @State private var isChecking = false
    @State private var checkedCount = 0
    @State private var summary: PlaylistHealthSummary?
    @State private var filter: HealthFilter = .all
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // ── Summary bar ──
            if let s = summary {
                summaryBar(s)
                Divider()
            }

            // ── Filter chips ──
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HealthFilter.allCases, id: \.self) { f in
                        FilterChip(label: f.label, isSelected: filter == f) { filter = f }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color.aetherSurface)

            Divider()

            // ── Results list ──
            if results.isEmpty && !isChecking {
                emptyState
            } else {
                resultsList
            }
        }
        .searchable(text: $searchText, prompt: "Filter channels…")
        .navigationTitle("Playlist Health")
        .toolbar { toolbarContent }
    }

    // MARK: - Summary bar

    @ViewBuilder
    private func summaryBar(_ s: PlaylistHealthSummary) -> some View {
        HStack(spacing: 20) {
            statBadge(label: "OK",    value: s.ok,    color: .green)
            statBadge(label: "Slow",  value: s.slow,  color: .orange)
            statBadge(label: "Dead",  value: s.dead,  color: .red)
            Spacer()
            Text("\(s.healthPercent)% healthy")
                .font(.aetherCaption.bold())
                .foregroundStyle(Color.aetherText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.aetherBackground)
    }

    private func statBadge(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label): \(value)")
                .font(.aetherCaption)
                .foregroundStyle(Color.aetherText)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Run a health check")
                .font(.aetherBody.bold())
                .foregroundStyle(Color.aetherText)
            Text("Ping all \(playlist.channels.count) streams to check availability and latency.")
                .font(.aetherCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results list

    private var filteredResults: [ChannelCheckResult] {
        var list = results
        switch filter {
        case .all:     break
        case .ok:      list = list.filter { guard case .ok   = $0.health else { return false }; return true }
        case .slow:    list = list.filter { guard case .slow = $0.health else { return false }; return true }
        case .dead:    list = list.filter { guard case .dead = $0.health else { return false }; return true }
        }
        if !searchText.isEmpty {
            list = list.filter { $0.channelName.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    private var resultsList: some View {
        List(filteredResults) { result in
            HealthRow(result: result)
        }
        .listStyle(.inset)
        .overlay(alignment: .top) {
            if isChecking {
                checkingProgressBar
            }
        }
    }

    // MARK: - Progress bar (shown while checking)

    private var checkingProgressBar: some View {
        VStack(spacing: 4) {
            ProgressView(
                value: Double(checkedCount),
                total: Double(max(playlist.channels.count, 1))
            )
            .progressViewStyle(.linear)
            .tint(Color.aetherPrimary)

            Text("Checking \(checkedCount) / \(playlist.channels.count)…")
                .font(.aetherCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color.aetherBackground)
    }

    @Environment(\.dismiss) private var dismiss

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await runCheck() }
            } label: {
                Label("Check Health", systemImage: "waveform.badge.magnifyingglass")
            }
            .disabled(isChecking)
            .help("Ping all streams")
        }
    }

    // MARK: - Health check action

    @MainActor
    private func runCheck() async {
        isChecking = true
        checkedCount = 0
        results = []
        summary = nil

        let channels: [(name: String, url: URL)] = playlist.channels.compactMap { record in
            guard let url = URL(string: record.streamURLString) else { return nil }
            return (name: record.name, url: url)
        }

        let validator = PlaylistValidator()
        let checked = await validator.validate(channels: channels) { checked, _ in
            Task { @MainActor in
                self.checkedCount = checked
            }
        }

        results = checked
        summary = PlaylistHealthSummary(results: checked)
        isChecking = false
    }
}

// MARK: - HealthRow

private struct HealthRow: View {
    let result: ChannelCheckResult

    private var healthColor: Color {
        switch result.health {
        case .ok:      return .green
        case .slow:    return .orange
        case .dead:    return .red
        case .unknown: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.health.icon)
                .foregroundStyle(healthColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.channelName)
                    .font(.aetherBody)
                    .foregroundStyle(Color.aetherText)
                    .lineLimit(1)

                Text(result.streamURL.host ?? result.streamURL.absoluteString)
                    .font(.aetherCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(result.health.label)
                .font(.aetherCaption.monospacedDigit())
                .foregroundStyle(healthColor)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Filter Chip (local)

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .white : Color.aetherText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.aetherPrimary : Color.aetherSurface, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : Color.aetherText.opacity(0.2),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter enum

private enum HealthFilter: CaseIterable {
    case all, ok, slow, dead

    var label: String {
        switch self {
        case .all:  return "All"
        case .ok:   return "✓ OK"
        case .slow: return "⚠ Slow"
        case .dead: return "✕ Dead"
        }
    }
}
