import SwiftUI
import SwiftData
import AetherCore

/// Middle column: channels grouped by `groupTitle`, with search + Favorites tab.
struct ChannelListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var epgStore: EPGStore

    let playlist: PlaylistRecord
    @Binding var selectedChannel: Channel?
    @ObservedObject var player: PlayerCore

    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var nowPlaying: [String: EPGEntry] = [:]  // channelID → current entry
    @State private var activeTab: ListTab = .all

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Tab switcher
            Picker("", selection: $activeTab) {
                ForEach(ListTab.allCases, id: \.self) { tab in
                    Label(tab.label, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch activeTab {
            case .all:
                allChannelsList
            case .favorites:
                FavoritesListView(player: player, selectedChannel: $selectedChannel)
            }
        }
        .searchable(text: $searchText, prompt: "Search channels")
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await refresh() } }) {
                    if isRefreshing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
                .help("Refresh Playlist")
            }
        }
        .task {
            if playlist.channels.isEmpty { await refresh() }
            await refreshEPG()
        }
    }

    // MARK: - All Channels List

    private var allChannelsList: some View {
        List(selection: $selectedChannel) {
            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            ForEach(groupedChannels, id: \.group) { section in
                Section(section.group) {
                    ForEach(section.channels) { record in
                        if let channel = record.toChannel() {
                            ChannelRow(
                                channel: channel,
                                isPlaying: player.currentChannel == channel,
                                epgEntry: nowPlaying[record.epgId ?? record.name]
                            )
                            .tag(channel)
                            .onTapGesture { selectAndPlay(channel) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grouped channels

    private var groupedChannels: [(group: String, channels: [ChannelRecord])] {
        let filtered: [ChannelRecord]
        if searchText.isEmpty {
            filtered = playlist.channels
        } else {
            filtered = playlist.channels.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        let sorted = filtered.sorted { $0.sortIndex < $1.sortIndex }
        let grouped = Dictionary(grouping: sorted) { $0.groupTitle }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, channels: $0.value) }
    }

    // MARK: - Actions

    private func selectAndPlay(_ channel: Channel) {
        selectedChannel = channel
        // Keep channelList in sync for prev/next navigation
        let flat = groupedChannels.flatMap(\.channels).compactMap { $0.toChannel() }
        player.channelList = flat
        player.play(channel)
    }

    @MainActor
    private func refresh() async {
        guard let url = playlist.effectiveURL else {
            errorMessage = "Invalid playlist URL"
            return
        }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            let service = PlaylistService()
            let channels = try await service.fetchChannels(from: url, forceRefresh: true)

            for old in playlist.channels { modelContext.delete(old) }
            playlist.channels = channels.enumerated().map { idx, ch in
                ChannelRecord(
                    id: ch.id,
                    name: ch.name,
                    streamURLString: ch.streamURL.absoluteString,
                    logoURLString: ch.logoURL?.absoluteString,
                    groupTitle: ch.groupTitle,
                    epgId: ch.epgId,
                    sortIndex: idx
                )
            }
            playlist.lastRefreshed = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshEPG() async {
        var entries: [String: EPGEntry] = [:]
        let now = Date()
        for record in playlist.channels {
            let cid = record.epgId ?? record.name
            if let entry = await epgStore.service.nowPlaying(for: cid, at: now) {
                entries[cid] = entry
            }
        }
        nowPlaying = entries
    }
}

// MARK: - Tab enum

private enum ListTab: String, CaseIterable {
    case all, favorites

    var label: String {
        switch self {
        case .all:       return "All"
        case .favorites: return "Favorites"
        }
    }
    var icon: String {
        switch self {
        case .all:       return "list.bullet"
        case .favorites: return "star.fill"
        }
    }
}

// MARK: - FavoritesListView

private struct FavoritesListView: View {
    @Query(sort: \FavoriteRecord.addedAt, order: .reverse) private var favorites: [FavoriteRecord]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var player: PlayerCore
    @Binding var selectedChannel: Channel?

    var body: some View {
        List(selection: $selectedChannel) {
            if favorites.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "star",
                    description: Text("Tap ★ in the player to save a channel here.")
                )
            } else {
                ForEach(favorites) { fav in
                    if let channel = fav.toChannel() {
                        ChannelRow(
                            channel: channel,
                            isPlaying: player.currentChannel == channel,
                            epgEntry: nil
                        )
                        .tag(channel)
                        .onTapGesture { play(channel) }
                    }
                }
                .onDelete { offsets in
                    for idx in offsets { modelContext.delete(favorites[idx]) }
                }
            }
        }
    }

    private func play(_ channel: Channel) {
        selectedChannel = channel
        player.channelList = favorites.compactMap { $0.toChannel() }
        player.play(channel)
    }
}

// MARK: - ChannelRow

/// A single row in the channel list.
struct ChannelRow: View {
    let channel: Channel
    let isPlaying: Bool
    let epgEntry: EPGEntry?

    var body: some View {
        HStack(spacing: 10) {
            ChannelLogoView(url: channel.logoURL, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.aetherBody)
                    .foregroundStyle(isPlaying ? Color.aetherPrimary : Color.aetherText)
                    .lineLimit(1)

                if let entry = epgEntry {
                    EPGProgressRow(entry: entry)
                } else if !channel.groupTitle.isEmpty {
                    Text(channel.groupTitle)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.aetherPrimary)
                    .symbolEffect(.variableColor.cumulative)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - EPGProgressRow

/// Compact EPG now-playing row with progress bar.
struct EPGProgressRow: View {
    let entry: EPGEntry
    @State private var progress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.aetherCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.aetherSurface)
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.aetherPrimary.opacity(0.7))
                        .frame(width: geo.size.width * progress, height: 3)
                }
            }
            .frame(height: 3)
        }
        .onAppear { progress = entry.progress() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            progress = entry.progress()
        }
    }
}
