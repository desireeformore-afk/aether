     1|import SwiftUI
     2|import SwiftData
     3|import AetherCore
     4|
     5|/// Middle column: channels grouped by `groupTitle`, with search, genre filter chips,
     6|/// collapsible sections, and Favorites tab.
     7|///
     8|/// Channel data lives in-memory — persisted to JSON via `ChannelCache`.
     9|/// Uses virtualized List with lazy sections to handle 50k+ channels efficiently.
    10|struct ChannelListView: View {
    11|    @Environment(\.modelContext) private var modelContext
    12|    @EnvironmentObject private var epgStore: EPGStore
    13|    @EnvironmentObject private var parentalService: ParentalControlService
    14|    @EnvironmentObject private var analyticsService: AnalyticsService
    15|
    16|    let playlist: PlaylistRecord
    17|    @Binding var selectedChannel: Channel?
    18|    @Bindable var player: PlayerCore
    19|
    20|    @State private var channels: [Channel] = []
    21|    @State private var searchText = ""
    22|    @State private var selectedGroup: String? = nil
    23|    @State private var selectedCategory: ContentCategory = .all
    24|    @State private var isRefreshing = false
    25|    @State private var errorMessage: String?
    26|    @State private var nowPlaying: [String: EPGEntry] = [:]
    27|    @State private var activeTab: ListTab = .all
    28|    @State private var collapsedGroups: Set<String> = []
    29|    @State private var viewMode: ChannelViewMode = .list
    30|    @FocusState private var isSearchFocused: Bool
    31|    @StateObject private var recommendationService: RecommendationService
    32|
    33|    @AppStorage("channelViewMode") private var savedViewMode: String = ChannelViewMode.list.rawValue
    34|    
    35|    // Persist collapsed groups per playlist
    36|    private var collapsedGroupsKey: String {
    37|        "collapsedGroups_\(playlist.id.uuidString)"
    38|    }
    39|
    40|    // Pagination for large playlists
    41|    @State private var displayedChannelCount = 100
    42|    private let batchSize = 100
    43|
    44|    // Memoized derived state — recomputed only when channels/search/group changes
    45|    @State private var cachedGrouped: [(group: String, channels: [Channel])] = []
    46|    @State private var cachedAllGroups: [String] = []
    47|
    48|    init(playlist: PlaylistRecord, selectedChannel: Binding<Channel?>, player: PlayerCore) {
    49|        self.playlist = playlist
    50|        self._selectedChannel = selectedChannel
    51|        self.player = player
    52|        // Initialize recommendation service with analytics
    53|        let analytics = AnalyticsService()
    54|        _recommendationService = StateObject(wrappedValue: RecommendationService(analyticsService: analytics))
    55|    }
    56|
    57|    // Search debouncing
    58|    @State private var searchDebounceTask: Task<Void, Never>?
    59|
    60|    // MARK: - Body
    61|
    62|    var body: some View {
    63|        VStack(spacing: 0) {
    64|            Picker("", selection: $activeTab) {
    65|                ForEach(ListTab.allCases, id: \.self) { tab in
    66|                    Label(tab.label, systemImage: tab.icon).tag(tab)
    67|                }
    68|            }
    69|            .pickerStyle(.segmented)
    70|            .padding(.horizontal, 12)
    71|            .padding(.vertical, 8)
    72|
    73|            Divider()
    74|
    75|            switch activeTab {
    76|            case .all:
    77|                allChannelsList
    78|            case .favorites:
    79|                FavoritesListView(player: player, selectedChannel: $selectedChannel)
    80|            case .recommended:
    81|                recommendedChannelsList
    82|            }
    83|        }
    84|        .searchable(text: $searchText, prompt: "Search channels")
    85|        .navigationTitle(playlist.name)
    86|        .toolbar {
    87|            ToolbarItem(placement: .primaryAction) {
    88|                // View mode toggle
    89|                Picker("View Mode", selection: $viewMode) {
    90|                    ForEach(ChannelViewMode.allCases, id: \.self) { mode in
    91|                        Label(mode.label, systemImage: mode.icon).tag(mode)
    92|                    }
    93|                }
    94|                .pickerStyle(.segmented)
    95|                .help("Toggle View Mode")
    96|            }
    97|
    98|            ToolbarItem(placement: .primaryAction) {
    99|                Button(action: { Task { await refresh() } }) {
   100|                    if isRefreshing {
   101|                        ProgressView().scaleEffect(0.7)
   102|                    } else {
   103|                        Image(systemName: "arrow.clockwise")
   104|                    }
   105|                }
   106|                .disabled(isRefreshing)
   107|                .help("Refresh Playlist")
   108|            }
   109|            ToolbarItem(placement: .primaryAction) {
   110|                NavigationLink {
   111|                    PlaylistHealthView(playlist: playlist, channels: channels)
   112|                } label: {
   113|                    Image(systemName: "waveform.badge.magnifyingglass")
   114|                }
   115|                .help("Check Playlist Health")
   116|            }
   117|        }
   118|        #if os(macOS)
   119|        .onKeyPress(.init("f"), phases: .down) { event in
   120|            guard event.modifiers.contains(.command) else { return .ignored }
   121|            isSearchFocused = true
   122|            return .handled
   123|        }
   124|        #endif
   125|        .task {
   126|            // Load saved view mode
   127|            if let mode = ChannelViewMode(rawValue: savedViewMode) {
   128|                viewMode = mode
   129|            }
   130|            
   131|            // Load collapsed groups state
   132|            if let data = UserDefaults.standard.data(forKey: collapsedGroupsKey),
   133|               let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
   134|                collapsedGroups = decoded
   135|            }
   136|
   137|            await loadFromCache()
   138|            let cacheAge = await ChannelCache.shared.lastModified(playlistID: playlist.id)
   139|                .map { Date().timeIntervalSince($0) } ?? .infinity
   140|            if channels.isEmpty || cacheAge > 3600 {
   141|                await refresh()
   142|            }
   143|            await refreshEPG()
   144|        }
   145|        .onChange(of: viewMode) { _, newMode in
   146|            savedViewMode = newMode.rawValue
   147|        }
   148|        .onChange(of: collapsedGroups) { _, newGroups in
   149|            if let encoded = try? JSONEncoder().encode(newGroups) {
   150|                UserDefaults.standard.set(encoded, forKey: collapsedGroupsKey)
   151|            }
   152|        }
   153|        // Recompute memoized lists whenever inputs change
   154|        .onChange(of: channels)      { _, _ in
   155|            displayedChannelCount = 100  // Reset pagination on new data
   156|            recomputeFiltered()
   157|        }
   158|        .onChange(of: searchText)    { _, _ in debouncedRecompute() }
   159|        .onChange(of: selectedGroup) { _, _ in recomputeFiltered() }
   160|        .onChange(of: selectedCategory) { _, _ in recomputeFiltered() }
   161|    }
   162|
   163|    // MARK: - Search debouncing
   164|
   165|    private func debouncedRecompute() {
   166|        searchDebounceTask?.cancel()
   167|        searchDebounceTask = Task {
   168|            try? await Task.sleep(for: .milliseconds(150))
   169|            guard !Task.isCancelled else { return }
   170|            recomputeFiltered()
   171|        }
   172|    }
   173|
   174|    // MARK: - Memoized filter (runs off main thread via Task)
   175|
   176|    private func recomputeFiltered() {
   177|        let snap = channels
   178|        let q = searchText.lowercased()
   179|        let grp = selectedGroup
   180|        let cat = selectedCategory
   181|        let maxDisplay = displayedChannelCount
   182|
   183|        Task.detached(priority: .userInitiated) {
   184|            // All groups (stable order, dedup)
   185|            var seenG = Set<String>()
   186|            let allG = snap.compactMap { ch -> String? in
   187|                seenG.insert(ch.groupTitle).inserted ? ch.groupTitle : nil
   188|            }
   189|
   190|            // Filtered
   191|            var result = snap
   192|            
   193|            // Category filter
   194|            switch cat {
   195|            case .all:
   196|                break
   197|            case .tv:
   198|                result = result.filter { ch in
   199|                    let g = ch.groupTitle.lowercased()
   200|                    return !g.contains("movie") && !g.contains("film") && !g.contains("series") && !g.contains("serial")
   201|                }
   202|            case .movies:
   203|                result = result.filter { ch in
   204|                    let g = ch.groupTitle.lowercased()
   205|                    return g.contains("movie") || g.contains("film") || g.contains("vod")
   206|                }
   207|            case .series:
   208|                result = result.filter { ch in
   209|                    let g = ch.groupTitle.lowercased()
   210|                    return g.contains("series") || g.contains("serial") || g.contains("show")
   211|                }
   212|            }
   213|            
   214|            if let group = grp { result = result.filter { $0.groupTitle == group } }
   215|            if !q.isEmpty      { result = result.filter { $0.name.lowercased().contains(q) } }
   216|
   217|            // Apply pagination only when not searching and no group filter
   218|            let shouldPaginate = q.isEmpty && grp == nil && result.count > maxDisplay
   219|            if shouldPaginate {
   220|                result = Array(result.prefix(maxDisplay))
   221|            }
   222|
   223|            // Group
   224|            var order: [String] = []
   225|            var dict: [String: [Channel]] = [:]
   226|            for ch in result {
   227|                if dict[ch.groupTitle] == nil {
   228|                    order.append(ch.groupTitle)
   229|                    dict[ch.groupTitle] = []
   230|                }
   231|                dict[ch.groupTitle]!.append(ch)
   232|            }
   233|            let grouped = order.map { (group: $0, channels: dict[$0]!) }
   234|
   235|            await MainActor.run {
   236|                cachedAllGroups = allG
   237|                cachedGrouped = grouped
   238|            }
   239|        }
   240|    }
   241|
   242|    // MARK: - Load from cache
   243|
   244|    @MainActor
   245|    private func loadFromCache() async {
   246|        let cached = await ChannelCache.shared.load(playlistID: playlist.id)
   247|        if !cached.isEmpty {
   248|            channels = cached
   249|            // Generate recommendations when channels are loaded
   250|            Task {
   251|                await recommendationService.generateRecommendations(for: channels)
   252|            }
   253|        }
   254|    }
   255|
   256|    // MARK: - Recommended Channels List
   257|
   258|    private var recommendedChannelsList: some View {
   259|        VStack(spacing: 0) {
   260|            if recommendationService.recommendations.isEmpty {
   261|                emptyRecommendationsView
   262|            } else {
   263|                recommendationsScrollView
   264|            }
   265|        }
   266|    }
   267|    
   268|    private var emptyRecommendationsView: some View {
   269|        VStack(spacing: 12) {
   270|            if recommendationService.isGenerating {
   271|                ProgressView()
   272|                    .scaleEffect(1.2)
   273|                Text("Generating recommendations...")
   274|                    .font(.subheadline)
   275|                    .foregroundStyle(.secondary)
   276|            } else {
   277|                Image(systemName: "sparkles")
   278|                    .font(.system(size: 48))
   279|                    .foregroundStyle(.secondary)
   280|                Text("No recommendations yet")
   281|                    .font(.headline)
   282|                Text("Watch some channels to get personalized recommendations")
   283|                    .font(.subheadline)
   284|                    .foregroundStyle(.secondary)
   285|                    .multilineTextAlignment(.center)
   286|            }
   287|        }
   288|        .frame(maxWidth: .infinity, maxHeight: .infinity)
   289|    }
   290|    
   291|    private var recommendationsScrollView: some View {
   292|        ScrollView {
   293|            LazyVStack(spacing: 0) {
   294|                ForEach(recommendationService.recommendations) { recommendation in
   295|                    if let channel = channels.first(where: { $0.name == recommendation.channelName }) {
   296|                        ChannelRow(
   297|                            channel: channel,
   298|                            nowPlaying: nowPlaying[channel.id],
   299|                            onPlay: { play(channel) }
   300|                        )
   301|                        Divider()
   302|                    }
   303|                }
   304|            }
   305|        }
   306|    }
   307|
   308|    // MARK: - All Channels List
   309|
   310|    private var allChannelsList: some View {
   311|        VStack(spacing: 0) {
   312|            // Category filter (TV/Movies/Series)
   313|            if searchText.isEmpty {
   314|                ScrollView(.horizontal, showsIndicators: false) {
   315|                    HStack(spacing: 8) {
   316|                        ForEach(ContentCategory.allCases, id: \.self) { category in
   317|                            FilterChip(label: category.label, isSelected: selectedCategory == category) {
   318|                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
   319|                                    selectedCategory = category
   320|                                }
   321|                            }
   322|                        }
   323|                    }
   324|                    .padding(.horizontal, 12)
   325|                    .padding(.vertical, 6)
   326|                }
   327|                .background(Color.aetherSurface)
   328|                Divider()
   329|            }
   330|            
   331|            // Genre filter chips (only when not searching)
   332|            if cachedAllGroups.count > 1 && searchText.isEmpty {
   333|                ScrollView(.horizontal, showsIndicators: false) {
   334|                    HStack(spacing: 8) {
   335|                        FilterChip(label: "All", isSelected: selectedGroup == nil) {
   336|                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
   337|                                selectedGroup = nil
   338|                            }
   339|                        }
   340|                        ForEach(cachedAllGroups, id: \.self) { group in
   341|                            FilterChip(label: group, isSelected: selectedGroup == group) {
   342|                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
   343|                                    selectedGroup = (selectedGroup == group) ? nil : group
   344|                                }
   345|                            }
   346|                        }
   347|                    }
   348|                    .padding(.horizontal, 12)
   349|                    .padding(.vertical, 6)
   350|                }
   351|                .background(Color.aetherSurface)
   352|                Divider()
   353|            }
   354|
   355|            if let err = errorMessage {
   356|                errorBanner(err)
   357|            }
   358|
   359|            if channels.isEmpty && !isRefreshing {
   360|                emptyState
   361|            } else {
   362|                switch viewMode {
   363|                case .list:
   364|                    channelListView
   365|                case .grid:
   366|                    channelGridView
   367|                }
   368|            }
   369|        }
   370|    }
   371|
   372|    // MARK: - Channel list (virtualized)
   373|
   374|    private var channelListView: some View {
   375|        List(selection: $selectedChannel) {
   376|            if !searchText.isEmpty {
   377|                // Flat list when searching — fully lazy, OS only renders visible rows
   378|                ForEach(cachedGrouped.flatMap(\.channels)) { ch in
   379|                    channelRow(ch).tag(ch)
   380|                }
   381|            } else {
   382|                // Grouped — collapsed sections keep row count low
   383|                ForEach(cachedGrouped, id: \.group) { section in
   384|                    Section {
   385|                        if !collapsedGroups.contains(section.group) {
   386|                            ForEach(section.channels) { ch in
   387|                                channelRow(ch).tag(ch)
   388|                            }
   389|                        }
   390|                    } header: {
   391|                        sectionHeader(section)
   392|                    }
   393|                }
   394|
   395|                // Load More button for pagination
   396|                if shouldShowLoadMore {
   397|                    Section {
   398|                        Button(action: loadMoreChannels) {
   399|                            HStack {
   400|                                Spacer()
   401|                                Label("Load More Channels", systemImage: "arrow.down.circle")
   402|                                    .font(.aetherBody)
   403|                                    .foregroundStyle(Color.aetherPrimary)
   404|                                Spacer()
   405|                            }
   406|                            .padding(.vertical, 8)
   407|                        }
   408|                        .buttonStyle(.plain)
   409|                    }
   410|                }
   411|            }
   412|        }
   413|        .listStyle(.inset)
   414|        .overlay(alignment: .top) {
   415|            if isRefreshing {
   416|                ProgressView()
   417|                    .scaleEffect(0.8)
   418|                    .padding(8)
   419|                    .background(.ultraThinMaterial, in: Capsule())
   420|                    .padding(.top, 8)
   421|            }
   422|        }
   423|    }
   424|
   425|    // MARK: - Channel grid view
   426|
   427|    private var channelGridView: some View {
   428|        ChannelGridView(
   429|            channels: cachedGrouped.flatMap(\.channels),
   430|            selectedChannel: selectedChannel,
   431|            onSelect: { channel in
   432|                play(channel)
   433|            },
   434|            nowPlaying: nowPlaying
   435|        )
   436|        .overlay(alignment: .top) {
   437|            if isRefreshing {
   438|                ProgressView()
   439|                    .scaleEffect(0.8)
   440|                    .padding(8)
   441|                    .background(.ultraThinMaterial, in: Capsule())
   442|                    .padding(.top, 8)
   443|            }
   444|        }
   445|    }
   446|
   447|    private var shouldShowLoadMore: Bool {
   448|        searchText.isEmpty && selectedGroup == nil && displayedChannelCount < channels.count
   449|    }
   450|
   451|    private func loadMoreChannels() {
   452|        withAnimation {
   453|            displayedChannelCount = min(displayedChannelCount + batchSize, channels.count)
   454|        }
   455|        recomputeFiltered()
   456|    }
   457|
   458|    private func sectionHeader(_ section: (group: String, channels: [Channel])) -> some View {
   459|        let collapsed = collapsedGroups.contains(section.group)
   460|        return Button {
   461|            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
   462|                if collapsed {
   463|                    collapsedGroups.remove(section.group)
   464|                } else {
   465|                    collapsedGroups.insert(section.group)
   466|                }
   467|            }
   468|        } label: {
   469|            HStack {
   470|                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
   471|                    .font(.system(size: 10, weight: .semibold))
   472|                    .foregroundStyle(.secondary)
   473|                Text(section.group)
   474|                    .font(.aetherCaption.bold())
   475|                    .foregroundStyle(.secondary)
   476|                Spacer()
   477|                Text("\(section.channels.count)")
   478|                    .font(.aetherCaption)
   479|                    .foregroundStyle(.tertiary)
   480|            }
   481|            .contentShape(Rectangle())
   482|        }
   483|        .buttonStyle(.plain)
   484|    }
   485|
   486|    private func channelRow(_ ch: Channel) -> some View {
   487|        let epgKey = ch.epgId ?? ch.name
   488|        let isBlocked = parentalService.settings.isEnabled && !parentalService.isChannelAllowed(ch)
   489|
   490|        return HStack {
   491|            ChannelRow(
   492|                channel: ch,
   493|                isPlaying: player.currentChannel == ch,
   494|                epgEntry: nowPlaying[epgKey],
   495|                showFavoriteButton: true
   496|            )
   497|
   498|            if isBlocked {
   499|                Image(systemName: "lock.fill")
   500|                    .font(.caption)
   501|