import SwiftUI
import SwiftData
import AetherCore

/// Middle column: channels grouped by `groupTitle`, with search, genre filter chips,
/// collapsible DisclosureGroup sections, and Favorites tab.
///
/// Channel data lives in-memory only — persisted to JSON via `ChannelCache`,
/// never in SwiftData (which can't handle 50k+ records efficiently).
struct ChannelListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var epgStore: EPGStore

    let playlist: PlaylistRecord
    @Binding var selectedChannel: Channel?
    @ObservedObject var player: PlayerCore

    @State private var channels: [Channel] = []
    @State private var searchText = ""
    @State private var selectedGroup: String? = nil
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var nowPlaying: [String: EPGEntry] = [:]
    @State private var activeTab: ListTab = .all
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
                    PlaylistHealthView(playlist: playlist, channels: channels)
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
            // 1. Load from cache instantly (no network)
            await loadFromCache()
            // 2. Refresh from network in background if cache is stale (>1h) or empty
            let cacheAge = await ChannelCache.shared.lastModified(playlistID: playlist.id)
                .map { Date().timeIntervalSince($0) } ?? .infinity
            if channels.isEmpty || cacheAge > 3600 {
                await refresh()
            }
            await refreshEPG()
        }
    }

    // MARK: - Load from cache

    @MainActor
    private func loadFromCache() async {
        let cached = await ChannelCache.shared.load(playlistID: playlist.id)
        if !cached.isEmpty {
            channels = cached
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedGroup = nil
                            }
                        }
                        ForEach(allGroups, id: \.self) { group in
                            FilterChip(label: group, isSelected: selectedGroup == group) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedGroup = (selectedGroup == group) ? nil : group
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(Color.aetherSurface)
                Divider()
            }

            if let err = errorMessage {
                errorBanner(err)
            }

            if channels.isEmpty && !isRefreshing {
                emptyState
            } else {
                channelList
            }
        }
    }

    // MARK: - Derived data

    private var allGroups: [String] {
        var seen = Set<String>()
        return channels.compactMap { ch in
            seen.insert(ch.groupTitle).inserted ? ch.groupTitle : nil
        }
    }

    private var filteredChannels: [Channel] {
        var result = channels
        if let group = selectedGroup {
            result = result.filter { $0.groupTitle == group }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(q) }
        }
        return result
    }

    private var groupedChannels: [(group: String, channels: [Channel])] {
        var order: [String] = []
        var dict: [String: [Channel]] = [:]
        for ch in filteredChannels {
            if dict[ch.groupTitle] == nil {
                order.append(ch.groupTitle)
                dict[ch.groupTitle] = []
            }
            dict[ch.groupTitle]!.append(ch)
        }
        return order.map { (group: $0, channels: dict[$0]!) }
    }

    // MARK: - Channel list

    private var channelList: some View {
        List(selection: $selectedChannel) {
            if !searchText.isEmpty {
                // Flat list when searching
                ForEach(filteredChannels) { ch in
                    channelRow(ch)
                        .tag(ch)
                }
            } else {
                // Grouped with DisclosureGroup
                ForEach(groupedChannels, id: \.group) { section in
                    let isExpanded = Binding<Bool>(
                        get: { expandedGroups[section.group] ?? true },
                        set: { expandedGroups[section.group] = $0 }
                    )
                    DisclosureGroup(isExpanded: isExpanded) {
                        ForEach(section.channels) { ch in
                            channelRow(ch)
                                .tag(ch)
                        }
                    } label: {
                        HStack {
                            Text(section.group)
                                .font(.aetherCaption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(section.channels.count)")
                                .font(.aetherCaption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay(alignment: .top) {
            if isRefreshing {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    private func channelRow(_ ch: Channel) -> some View {
        let epgKey = ch.epgId ?? ch.name
        return ChannelRow(
            channel: ch,
            isPlaying: player.currentChannel == ch,
            epgEntry: nowPlaying[epgKey]
        )
        .onTapGesture { play(ch) }
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Channels", systemImage: "tv.slash")
        } description: {
            Text("Pull to refresh or tap ↻ to load channels.")
        } actions: {
            Button("Refresh") { Task { await refresh() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(msg)
                .font(.aetherCaption)
                .foregroundStyle(Color.aetherText)
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Playback

    private func play(_ channel: Channel) {
        selectedChannel = channel
        player.channelList = filteredChannels
        player.play(channel)
    }

    // MARK: - Refresh (network fetch → cache → in-memory)

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            let fetched: [Channel]

            if playlist.playlistType == .xtream, let creds = playlist.xstreamCredentials {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 30
                config.timeoutIntervalForResource = 120
                let session = URLSession(configuration: config)
                let service = XstreamService(credentials: creds, session: session)
                fetched = try await service.channels()
            } else {
                guard let url = playlist.effectiveURL else {
                    errorMessage = "Invalid playlist URL"
                    return
                }
                fetched = try await PlaylistService().fetchChannels(from: url, forceRefresh: true)
            }

            // Update in-memory first (instant UI update)
            channels = fetched

            // Persist to JSON cache in background (non-blocking)
            let playlistID = playlist.id
            Task.detached(priority: .background) {
                try? await ChannelCache.shared.save(channels: fetched, playlistID: playlistID)
            }

            playlist.lastRefreshed = Date()
            expandedGroups = [:]

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - EPG

    @MainActor
    private func refreshEPG() async {
        var entries: [String: EPGEntry] = [:]
        let now = Date()
        for ch in channels.prefix(500) { // limit EPG lookups
            let cid = ch.epgId ?? ch.name
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
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
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
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .shadow(
                    color: isSelected ? Color.aetherPrimary.opacity(0.35) : .clear,
                    radius: 4, y: 2
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
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
