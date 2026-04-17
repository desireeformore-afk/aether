import SwiftUI
import SwiftData
import AetherCore

/// Middle column: channels grouped by `groupTitle`, with search, genre filter chips,
/// collapsible DisclosureGroup sections, and Favorites tab.
struct ChannelListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var epgStore: EPGStore

    let playlist: PlaylistRecord
    @Binding var selectedChannel: Channel?
    @ObservedObject var player: PlayerCore

    @State private var searchText = ""
    @State private var selectedGroup: String? = nil
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var nowPlaying: [String: EPGEntry] = [:]
    @State private var activeTab: ListTab = .all
    /// Tracks which group sections are expanded (key: group name, value: isExpanded).
    @State private var expandedGroups: [String: Bool] = [:]
    @FocusState private var isSearchFocused: Bool

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
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    PlaylistHealthView(playlist: playlist)
                } label: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                }
                .help("Check Playlist Health")
            }
        }
        #if os(macOS)
        .onKeyPress(.init("f"), phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            isSearchFocused = true
            return .handled
        }
        #endif
        .task {
            if playlist.channels.isEmpty { await refresh() }
            await refreshEPG()
        }
    }

    // MARK: - All Channels List

    private var allChannelsList: some View {
        VStack(spacing: 0) {
            // Genre filter chips (only when not searching)
            if allGroups.count > 1 && searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: selectedGroup == nil) {
                            selectedGroup = nil
                        }
                        ForEach(allGroups, id: \.self) { group in
                            FilterChip(label: group, isSelected: selectedGroup == group) {
                                selectedGroup = (selectedGroup == group) ? nil : group
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(Color.aetherSurface)
                Divider()
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.aetherCaption)
                    .padding()
            }

            // When a single group filter is active or searching, show a flat list.
            // Otherwise show collapsible DisclosureGroup sections.
            if selectedGroup != nil || !searchText.isEmpty || groupedChannels.count == 1 {
                flatChannelList
            } else {
                collapsibleChannelList
            }
        }
    }

    // MARK: - Flat list (search / single-group mode)

    private var flatChannelList: some View {
        List(selection: $selectedChannel) {
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

    // MARK: - Collapsible DisclosureGroup list

    private var collapsibleChannelList: some View {
        List(selection: $selectedChannel) {
            ForEach(groupedChannels, id: \.group) { section in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedGroups[section.group] ?? true },
                        set: { expandedGroups[section.group] = $0 }
                    )
                ) {
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
                } label: {
                    HStack {
                        Text(section.group)
                            .font(.aetherBody.bold())
                            .foregroundStyle(Color.aetherText)
                        Spacer()
                        Text("\(section.channels.count)")
                            .font(.aetherCaption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Groups (via ChannelFilterService)

    private let filterService = ChannelFilterService()

    private var allGroups: [String] {
        let channels = playlist.channels.compactMap { $0.toChannel() }
        return filterService.groups(from: channels)
    }

    // MARK: - Grouped channels (via ChannelFilterService)

    private var groupedChannels: [(group: String, channels: [ChannelRecord])] {
        let allRecords = playlist.channels
        let allChannels = allRecords.compactMap { $0.toChannel() }

        let filteredChannels = filterService.filter(
            channels: allChannels,
            group: selectedGroup,
            searchQuery: searchText
        )

        let filteredIDs = Set(filteredChannels.map(\.id))
        let filteredRecords = allRecords
            .filter { filteredIDs.contains($0.id) }
            .sorted { $0.sortIndex < $1.sortIndex }

        let grouped = Dictionary(grouping: filteredRecords) { $0.groupTitle }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, channels: $0.value) }
    }

    // MARK: - Actions

    private func selectAndPlay(_ channel: Channel) {
        selectedChannel = channel
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
            // Reset expanded state for new groups
            expandedGroups = [:]
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

// MARK: - FilterChip

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
                .background(
                    isSelected
                        ? Color.aetherPrimary
                        : Color.aetherSurface,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.aetherText.opacity(0.2),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
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
            ChannelLogoView(url: channel.logoURL)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.aetherBody)
                    .foregroundStyle(isPlaying ? Color.aetherPrimary : Color.aetherText)
                    .lineLimit(1)

                if let entry = epgEntry {
                    Text(entry.title)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isPlaying {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(Color.aetherPrimary)
                    .symbolEffect(.variableColor.iterative)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
