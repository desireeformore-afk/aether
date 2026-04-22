import SwiftUI
import SwiftData
import AetherCore
import AetherUI

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
    @Environment(NetworkMonitorService.self) private var networkMonitor

    let playlist: PlaylistRecord
    @Binding var selectedChannel: Channel?
    @Bindable var player: PlayerCore
    /// Incremented externally (e.g., keyboard shortcut /) to activate search field.
    var searchActivationToken: Int = 0

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
    @State private var showPINLock = false
    @State private var blockedChannel: Channel? = nil

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

    // Cached favorite IDs — avoids per-row SwiftData fetch during list rendering
    @State private var cachedFavoriteIDs: Set<UUID> = []

    init(playlist: PlaylistRecord, selectedChannel: Binding<Channel?>, player: PlayerCore, searchActivationToken: Int = 0) {
        self.playlist = playlist
        self._selectedChannel = selectedChannel
        self.player = player
        self.searchActivationToken = searchActivationToken
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
            .onKeyPress(.escape) {
                player.stop()
                return .handled
            }
            #endif
            .onChange(of: searchActivationToken) { _, _ in
                isSearchFocused = true
            }
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

            refreshFavoriteCache()
            recommendationService = RecommendationService(analyticsService: analyticsService)
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
        // KEY FIX: macOS List consumes tap events — onTapGesture in rows is unreliable.
        // Use onChange(of: selectedChannel) — the List's native selection IS reliable.
        .onChange(of: selectedChannel) { _, newChannel in
            guard let ch = newChannel else { return }
            let isBlocked = parentalService.settings.isEnabled && !parentalService.isChannelAllowed(ch)
            if isBlocked {
                blockedChannel = ch
                showPINLock = true
            } else {
                player.play(ch)
                analyticsService.recordChannelSwitch()
            }
        }
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
        if !networkMonitor.isOnline {
            if !channels.isEmpty { return }
            errorMessage = "Brak połączenia z internetem"
            return
        }
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
        let favoriteChannels = channels.filter { cachedFavoriteIDs.contains($0.id) }
        
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
        .sheet(isPresented: $showPINLock) {
            PINLockView(
                reason: "This channel is restricted by parental controls",
                service: parentalService,
                onUnlock: {
                    if let ch = blockedChannel { player.play(ch) }
                    showPINLock = false
                    blockedChannel = nil
                },
                onCancel: {
                    showPINLock = false
                    blockedChannel = nil
                }
            )
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
                        ChannelRowView(
                            channel: channel,
                            isSelected: player.currentChannel == channel,
                            epgTitle: nowPlaying[channel.epgId ?? channel.name]?.title
                        )
                        .onTapGesture { play(channel) }
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
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(err).font(.caption)
                    Spacer()
                    Button("Dismiss") { errorMessage = nil }.font(.caption)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
            }

            // Empty state: channels loaded but active filter returns nothing
            let filteredEmpty = !channels.isEmpty && !isRefreshing && cachedGrouped.isEmpty
            if channels.isEmpty && isRefreshing {
                channelLoadingSkeleton
            } else if channels.isEmpty && !isRefreshing {
                VStack(spacing: 12) {
                    if !networkMonitor.isOnline {
                        Image(systemName: "wifi.slash").font(.system(size: 48)).foregroundStyle(.orange)
                        Text("Brak połączenia").font(.headline)
                        Text("Kanały zostaną załadowane po przywróceniu połączenia")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else {
                        Image(systemName: "tv").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No channels").font(.headline)
                        Text("Refresh the playlist or check your URL")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEmpty {
                VStack(spacing: 12) {
                    if !searchText.isEmpty {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("No results for \"\(searchText)\"")
                            .font(.headline)
                        Text("Try a different search term or clear the search")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Clear Search") { searchText = "" }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                    } else {
                        Image(systemName: selectedCategory == .movies ? "film" : selectedCategory == .series ? "tv.and.mediabox" : "tv.slash")
                            .font(.system(size: 40)).foregroundStyle(.secondary)
                        Text(selectedCategory == .movies ? "No movie channels in Live TV" : selectedCategory == .series ? "No series channels in Live TV" : "No channels match the filter")
                            .font(.headline)
                        if selectedCategory == .movies || selectedCategory == .series {
                            Text("Use the \(selectedCategory == .movies ? "VOD" : "Series") tab to browse \(selectedCategory == .movies ? "movies" : "series")")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Loading skeleton

    private var channelLoadingSkeleton: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { _ in
                    ChannelRowSkeletonView()
                    Divider()
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
        // Only show when no search, no group filter, no category filter active,
        // and there are more channels than currently displayed
        searchText.isEmpty
            && selectedGroup == nil
            && selectedCategory == .all
            && displayedChannelCount < channels.count
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
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(section.group.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    Spacer()
                    Text("\(section.channels.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)

                Divider()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func channelRow(_ ch: Channel) -> some View {
        let epgKey = ch.epgId ?? ch.name
        let isBlocked = parentalService.settings.isEnabled && !parentalService.isChannelAllowed(ch)
        let isFavorite = isFavoriteChannel(ch)
        let isActive = player.currentChannel == ch

        return ChannelRowContainer(
            channel: ch,
            isActive: isActive,
            isBlocked: isBlocked,
            isFavorite: isFavorite,
            epgTitle: nowPlaying[epgKey]?.title,
            onTap: {
                if isBlocked {
                    blockedChannel = ch
                    showPINLock = true
                } else {
                    play(ch)
                }
            },
            onFavoriteTap: { toggleFavorite(channel: ch) }
        )
        .id(ch.id)
    }

    private func isFavoriteChannel(_ channel: Channel) -> Bool {
        cachedFavoriteIDs.contains(channel.id)
    }

    private func refreshFavoriteCache() {
        let records = (try? modelContext.fetch(FetchDescriptor<FavoriteRecord>())) ?? []
        cachedFavoriteIDs = Set(records.map { $0.channelID })
    }

    private func toggleFavorite(channel: Channel) {
        let channelID = channel.id
        let existing = (try? modelContext.fetch(
            FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.channelID == channelID })
        )) ?? []
        if let record = existing.first {
            modelContext.delete(record)
            cachedFavoriteIDs.remove(channelID)
        } else {
            modelContext.insert(FavoriteRecord(channel: channel))
            cachedFavoriteIDs.insert(channelID)
        }
        try? modelContext.save()
    }

    private func play(_ channel: Channel) {
        selectedChannel = channel  // triggers onChange above which calls player.play()
        analyticsService.recordChannelSwitch()
    }
}

// MARK: - Supporting Types

enum ListTab: String, CaseIterable {
    case all = "All"
    case favorites = "Favorites"
    case recommended = "Recommended"

    var label: String { rawValue }

    var icon: String {
        switch self {
        case .all:         return "list.bullet"
        case .favorites:   return "star.fill"
        case .recommended: return "sparkles"
        }
    }
}

// MARK: - FilterChip (local copy — shared via AetherUI in future)

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

// MARK: - ChannelRowContainer (premium macOS channel row)

private struct ChannelRowContainer: View {
    let channel: Channel
    let isActive: Bool
    let isBlocked: Bool
    let isFavorite: Bool
    let epgTitle: String?
    let onTap: () -> Void
    let onFavoriteTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ChannelRowView(
                channel: channel,
                isSelected: isActive,
                epgTitle: epgTitle
            )

            if isBlocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(isActive ? .white.opacity(0.8) : .red)
                    .padding(.trailing, 6)
            }

            Button(action: onFavoriteTap) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        isFavorite
                            ? .yellow
                            : (isActive ? .white.opacity(0.5) : Color.secondary.opacity(0.35))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .background(
            Group {
                if isActive {
                    Color.accentColor
                } else if isHovered {
                    Color.white.opacity(0.08)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
    }
}

