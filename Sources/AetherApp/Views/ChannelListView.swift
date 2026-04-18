import SwiftUI
import SwiftData
import AetherCore

/// Middle column: channels grouped by `groupTitle`, with search, genre filter chips,
/// collapsible sections, and Favorites tab.
///
/// Channel data lives in-memory — persisted to JSON via `ChannelCache`.
/// Uses virtualized List with lazy sections to handle 50k+ channels efficiently.
struct ChannelListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var epgStore: EPGStore
    @EnvironmentObject private var parentalService: ParentalControlService
    @EnvironmentObject private var analyticsService: AnalyticsService

    let playlist: PlaylistRecord
    @Binding var selectedChannel: Channel?
    @ObservedObject var player: PlayerCore

    @State private var channels: [Channel] = []
    @State private var searchText = ""
    @State private var selectedGroup: String? = nil
    @State private var selectedCategory: ContentCategory = .all
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var nowPlaying: [String: EPGEntry] = [:]
    @State private var activeTab: ListTab = .all
    @State private var collapsedGroups: Set<String> = []
    @State private var viewMode: ChannelViewMode = .list
    @FocusState private var isSearchFocused: Bool
    @StateObject private var recommendationService: RecommendationService

    @AppStorage("channelViewMode") private var savedViewMode: String = ChannelViewMode.list.rawValue
    
    // Persist collapsed groups per playlist
    private var collapsedGroupsKey: String {
        "collapsedGroups_\(playlist.id.uuidString)"
    }

    // Pagination for large playlists
    @State private var displayedChannelCount = 100
    private let batchSize = 100

    // Memoized derived state — recomputed only when channels/search/group changes
    @State private var cachedGrouped: [(group: String, channels: [Channel])] = []
    @State private var cachedAllGroups: [String] = []

    init(playlist: PlaylistRecord, selectedChannel: Binding<Channel?>, player: PlayerCore) {
        self.playlist = playlist
        self._selectedChannel = selectedChannel
        self.player = player
        // Initialize recommendation service with analytics
        let analytics = AnalyticsService()
        _recommendationService = StateObject(wrappedValue: RecommendationService(analyticsService: analytics))
    }

    // Search debouncing
    @State private var searchDebounceTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
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
            case .recommended:
                recommendedChannelsList
            }
        }
        .searchable(text: $searchText, prompt: "Search channels")
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // View mode toggle
                Picker("View Mode", selection: $viewMode) {
                    ForEach(ChannelViewMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Toggle View Mode")
            }

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
            // Load saved view mode
            if let mode = ChannelViewMode(rawValue: savedViewMode) {
                viewMode = mode
            }
            
            // Load collapsed groups state
            if let data = UserDefaults.standard.data(forKey: collapsedGroupsKey),
               let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
                collapsedGroups = decoded
            }

            await loadFromCache()
            let cacheAge = await ChannelCache.shared.lastModified(playlistID: playlist.id)
                .map { Date().timeIntervalSince($0) } ?? .infinity
            if channels.isEmpty || cacheAge > 3600 {
                await refresh()
            }
            await refreshEPG()
        }
        .onChange(of: viewMode) { _, newMode in
            savedViewMode = newMode.rawValue
        }
        .onChange(of: collapsedGroups) { _, newGroups in
            if let encoded = try? JSONEncoder().encode(newGroups) {
                UserDefaults.standard.set(encoded, forKey: collapsedGroupsKey)
            }
        }
        // Recompute memoized lists whenever inputs change
        .onChange(of: channels)      { _, _ in
            displayedChannelCount = 100  // Reset pagination on new data
            recomputeFiltered()
        }
        .onChange(of: searchText)    { _, _ in debouncedRecompute() }
        .onChange(of: selectedGroup) { _, _ in recomputeFiltered() }
        .onChange(of: selectedCategory) { _, _ in recomputeFiltered() }
    }

    // MARK: - Search debouncing

    private func debouncedRecompute() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            recomputeFiltered()
        }
    }

    // MARK: - Memoized filter (runs off main thread via Task)

    private func recomputeFiltered() {
        let snap = channels
        let q = searchText.lowercased()
        let grp = selectedGroup
        let cat = selectedCategory
        let maxDisplay = displayedChannelCount

        Task.detached(priority: .userInitiated) {
            // All groups (stable order, dedup)
            var seenG = Set<String>()
            let allG = snap.compactMap { ch -> String? in
                seenG.insert(ch.groupTitle).inserted ? ch.groupTitle : nil
            }

            // Filtered
            var result = snap
            
            // Category filter
            switch cat {
            case .all:
                break
            case .tv:
                result = result.filter { ch in
                    let g = ch.groupTitle.lowercased()
                    return !g.contains("movie") && !g.contains("film") && !g.contains("series") && !g.contains("serial")
                }
            case .movies:
                result = result.filter { ch in
                    let g = ch.groupTitle.lowercased()
                    return g.contains("movie") || g.contains("film") || g.contains("vod")
                }
            case .series:
                result = result.filter { ch in
                    let g = ch.groupTitle.lowercased()
                    return g.contains("series") || g.contains("serial") || g.contains("show")
                }
            }
            
            if let group = grp { result = result.filter { $0.groupTitle == group } }
            if !q.isEmpty      { result = result.filter { $0.name.lowercased().contains(q) } }

            // Apply pagination only when not searching and no group filter
            let shouldPaginate = q.isEmpty && grp == nil && result.count > maxDisplay
            if shouldPaginate {
                result = Array(result.prefix(maxDisplay))
            }

            // Group
            var order: [String] = []
            var dict: [String: [Channel]] = [:]
            for ch in result {
                if dict[ch.groupTitle] == nil {
                    order.append(ch.groupTitle)
                    dict[ch.groupTitle] = []
                }
                dict[ch.groupTitle]!.append(ch)
            }
            let grouped = order.map { (group: $0, channels: dict[$0]!) }

            await MainActor.run {
                cachedAllGroups = allG
                cachedGrouped = grouped
            }
        }
    }

    // MARK: - Load from cache

    @MainActor
    private func loadFromCache() async {
        let cached = await ChannelCache.shared.load(playlistID: playlist.id)
        if !cached.isEmpty {
            channels = cached
            // Generate recommendations when channels are loaded
            Task {
                await recommendationService.generateRecommendations(for: channels)
            }
        }
    }

    // MARK: - Recommended Channels List

    private var recommendedChannelsList: some View {
        VStack(spacing: 0) {
            if recommendationService.recommendations.isEmpty {
                emptyRecommendationsView
            } else {
                recommendationsScrollView
            }
        }
    }
    
    private var emptyRecommendationsView: some View {
        VStack(spacing: 12) {
            if recommendationService.isGenerating {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Generating recommendations...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No recommendations yet")
                    .font(.headline)
                Text("Watch some channels to get personalized recommendations")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var recommendationsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(recommendationService.recommendations) { recommendation in
                    if let channel = channels.first(where: { $0.name == recommendation.channelName }) {
                        ChannelRow(
                            channel: channel,
                            nowPlaying: nowPlaying[channel.id],
                            onPlay: { play(channel) }
                        )
                        Divider()
                    }
                }
            }
        }
    }
    }

    // MARK: - All Channels List

    private var allChannelsList: some View {
        VStack(spacing: 0) {
            // Category filter (TV/Movies/Series)
            if searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ContentCategory.allCases, id: \.self) { category in
                            FilterChip(label: category.label, isSelected: selectedCategory == category) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedCategory = category
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
            
            // Genre filter chips (only when not searching)
            if cachedAllGroups.count > 1 && searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: selectedGroup == nil) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedGroup = nil
                            }
                        }
                        ForEach(cachedAllGroups, id: \.self) { group in
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
                switch viewMode {
                case .list:
                    channelListView
                case .grid:
                    channelGridView
                }
            }
        }
    }

    // MARK: - Channel list (virtualized)

    private var channelListView: some View {
        List(selection: $selectedChannel) {
            if !searchText.isEmpty {
                // Flat list when searching — fully lazy, OS only renders visible rows
                ForEach(cachedGrouped.flatMap(\.channels)) { ch in
                    channelRow(ch).tag(ch)
                }
            } else {
                // Grouped — collapsed sections keep row count low
                ForEach(cachedGrouped, id: \.group) { section in
                    Section {
                        if !collapsedGroups.contains(section.group) {
                            ForEach(section.channels) { ch in
                                channelRow(ch).tag(ch)
                            }
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }

                // Load More button for pagination
                if shouldShowLoadMore {
                    Section {
                        Button(action: loadMoreChannels) {
                            HStack {
                                Spacer()
                                Label("Load More Channels", systemImage: "arrow.down.circle")
                                    .font(.aetherBody)
                                    .foregroundStyle(Color.aetherPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
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

    // MARK: - Channel grid view

    private var channelGridView: some View {
        ChannelGridView(
            channels: cachedGrouped.flatMap(\.channels),
            selectedChannel: selectedChannel,
            onSelect: { channel in
                play(channel)
            },
            nowPlaying: nowPlaying
        )
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

    private var shouldShowLoadMore: Bool {
        searchText.isEmpty && selectedGroup == nil && displayedChannelCount < channels.count
    }

    private func loadMoreChannels() {
        withAnimation {
            displayedChannelCount = min(displayedChannelCount + batchSize, channels.count)
        }
        recomputeFiltered()
    }

    private func sectionHeader(_ section: (group: String, channels: [Channel])) -> some View {
        let collapsed = collapsedGroups.contains(section.group)
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                if collapsed {
                    collapsedGroups.remove(section.group)
                } else {
                    collapsedGroups.insert(section.group)
                }
            }
        } label: {
            HStack {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(section.group)
                    .font(.aetherCaption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(section.channels.count)")
                    .font(.aetherCaption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func channelRow(_ ch: Channel) -> some View {
        let epgKey = ch.epgId ?? ch.name
        let isBlocked = parentalService.settings.isEnabled && !parentalService.isChannelAllowed(ch)

        return HStack {
            ChannelRow(
                channel: ch,
                isPlaying: player.currentChannel == ch,
                epgEntry: nowPlaying[epgKey],
                showFavoriteButton: true
            )

            if isBlocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Restricted by parental controls")
            }
        }
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
                Image(systemName: "xmark").font(.caption2)
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
        // Pass only the current section's channels as navigation list (not all 50k)
        let navList = cachedGrouped
            .first(where: { $0.group == channel.groupTitle })?
            .channels ?? cachedGrouped.flatMap(\.channels)
        Task { @MainActor in
            player.channelList = navList
            player.play(channel)
        }
    }

    // MARK: - Refresh

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

            channels = fetched
            playlist.lastRefreshed = Date()
            collapsedGroups = []

            let playlistID = playlist.id
            Task.detached(priority: .background) {
                try? await ChannelCache.shared.save(channels: fetched, playlistID: playlistID)
            }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - EPG

    @MainActor
    private func refreshEPG() async {
        var entries: [String: EPGEntry] = [:]
        let now = Date()
        for ch in channels.prefix(500) {
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
                    isSelected ? Color.aetherPrimary : Color.aetherSurface,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : Color.aetherText.opacity(0.2),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
    }
}

// MARK: - Tab enum

private enum ListTab: String, CaseIterable {
    case all, favorites, recommended

    var label: String {
        switch self {
        case .all:       return "All"
        case .favorites: return "Favorites"
        case .recommended: return "For You"
        }
    }
    var icon: String {
        switch self {
        case .all:       return "list.bullet"
        case .favorites: return "star.fill"
        case .recommended: return "sparkles"
        }
    }
}

// MARK: - Content Category enum

private enum ContentCategory: String, CaseIterable {
    case all, tv, movies, series
    
    var label: String {
        switch self {
        case .all:    return "Wszystkie"
        case .tv:     return "TV"
        case .movies: return "Filmy"
        case .series: return "Seriale"
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
        Task { @MainActor in
            player.channelList = favorites.compactMap { $0.toChannel() }
            player.play(channel)
        }
    }
}

// MARK: - ChannelRow

struct ChannelRow: View {
    let channel: Channel
    let isPlaying: Bool
    let epgEntry: EPGEntry?
    var showFavoriteButton: Bool = false

    @Query private var favorites: [FavoriteRecord]
    @Environment(\.modelContext) private var modelContext

    private var isFavorite: Bool {
        favorites.contains { $0.channelID == channel.id }
    }

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

            if showFavoriteButton {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(isFavorite ? Color.aetherAccent : Color.aetherText.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }

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

    private func toggleFavorite() {
        if let existing = favorites.first(where: { $0.channelID == channel.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteRecord(channel: channel))
        }
    }
}
