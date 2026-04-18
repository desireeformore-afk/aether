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
    @Environment(EPGStore.self) private var epgStore
    @Environment(ParentalControlService.self) private var parentalService
    @Environment(AnalyticsService.self) private var analyticsService

    let playlist: PlaylistRecord
    @Binding var selectedChannel: Channel?
    @Bindable var player: PlayerCore

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
    @State private var recommendationService: RecommendationService

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
        // Initialize recommendation service with analytics - will be set from environment
        self.recommendationService = RecommendationService(analyticsService: AnalyticsService())
    }

    // Search debouncing
    @State private var searchDebounceTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        contentView
            .searchable(text: $searchText, prompt: "Search channels")
            .navigationTitle(playlist.name)
            .toolbar { toolbarContent }
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
                let service = XstreamService(credentials: creds)
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
            let id = playlist.id
            Task.detached(priority: .background) {
                try? await ChannelCache.shared.save(channels: fetched, playlistID: id)
            }
            // Generate recommendations after refresh
            await recommendationService.generateRecommendations(for: channels)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Favorites Channels List

    private var favoritesChannelsList: some View {
        let favoriteIDs = (try? modelContext.fetch(FetchDescriptor<FavoriteRecord>())) ?? []
        let favoriteChannelIDs = Set(favoriteIDs.map { $0.channelID })
        let favoriteChannels = channels.filter { favoriteChannelIDs.contains($0.id) }
        
        return VStack(spacing: 0) {
            if favoriteChannels.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No favorites yet")
                        .font(.headline)
                    Text("Tap the star icon on any channel to add it to favorites")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedChannel) {
                    ForEach(favoriteChannels) { ch in
                        channelRow(ch).tag(ch)
                    }
                }
            }
        }
    }

    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 0) {
            tabPicker
            Divider()
            tabContent
        }
    }
    
    private var tabPicker: some View {
        Picker("", selection: $activeTab) {
            ForEach(ListTab.allCases, id: \.self) { tab in
                Label(tab.label, systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .all:
            allChannelsList
        case .favorites:
            favoritesChannelsList
        case .recommended:
            recommendedChannelsList
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
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
                    .foregroundStyle(.red)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isBlocked {
                parentalService.requestUnlock()
            } else {
                selectedChannel = ch
                player.play(ch)
                analyticsService.trackChannelPlay(ch)
            }
        }
    }
}

// MARK: - Supporting Types

enum ListTab: String, CaseIterable {
    case all = "All"
    case favorites = "Favorites"
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .favorites: return "star.fill"
        }
    }
}


