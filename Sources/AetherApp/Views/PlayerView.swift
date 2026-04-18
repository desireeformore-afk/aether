     1|import SwiftUI
     2|import SwiftData
     3|import AVKit
     4|import AetherCore
     5|import AetherUI
     6|
     7|/// Detail pane: AVPlayer video + transport controls + EPG info bar + timeline.
     8|struct PlayerView: View {
     9|    @EnvironmentObject private var epgStore: EPGStore
    10|    @EnvironmentObject private var sleepTimer: SleepTimerService
    11|    @EnvironmentObject private var subtitleStore: SubtitleStore
    12|    @EnvironmentObject private var parentalService: ParentalControlService
    13|
    14|    @Bindable var player: PlayerCore
    15|
    16|    @State private var nowPlaying: EPGEntry?
    17|    @State private var nextUp: EPGEntry?
    18|    /// All EPG entries for the current channel (may span multiple days).
    19|    @State private var allEPGEntries: [EPGEntry] = []
    20|    @State private var showStats = false
    21|    @State private var showTimeline = false
    22|    /// Cancellation token for in-flight EPG fetch (debounce for rapid channel changes).
    23|    @State private var epgFetchTask: Task<Void, Never>?
    24|    /// EPG timeline overlay visibility (hover/interaction)
    25|    @State private var showEPGOverlay = false
    26|    /// Auto-hide timer for EPG overlay
    27|    @State private var overlayHideTask: Task<Void, Never>?
    28|    /// Parental control lock state
    29|    @State private var showPINLock = false
    30|    @State private var blockedChannel: Channel?
    31|    @State private var blockReason: String?
    32|
    33|    var body: some View {
    34|        ZStack {
    35|            Color.aetherBackground.ignoresSafeArea()
    36|
    37|            VStack(spacing: 0) {
    38|                // Video layer
    39|                ZStack(alignment: .bottom) {
    40|                    VideoPlayerLayer(avPlayer: player.player, playerCore: player)
    41|                        .aspectRatio(16 / 9, contentMode: .fit)
    42|                        .clipShape(RoundedRectangle(cornerRadius: 8))
    43|                        .overlay(alignment: .bottomLeading) {
    44|                            stateOverlay
    45|                                .padding([.horizontal, .bottom], 20)
    46|                        }
    47|                        .overlay(alignment: .bottom) {
    48|                            // EPG Timeline Overlay (bottom, auto-hide)
    49|                            if showEPGOverlay, let current = nowPlaying {
    50|                                EPGTimelineOverlay(current: current, next: nextUp)
    51|                                    .padding(.horizontal, 20)
    52|                                    .padding(.bottom, 16)
    53|                                    .transition(.move(edge: .bottom).combined(with: .opacity))
    54|                            }
    55|                        }
    56|                        .onHover { hovering in
    57|                            if hovering {
    58|                                showEPGOverlayWithAutoHide()
    59|                            }
    60|                        }
    61|
    62|                    // Subtitle overlay — non-interactive
    63|                    SubtitleOverlayView(store: subtitleStore)
    64|
    65|                    // Stream stats HUD — top-trailing corner
    66|                    if showStats {
    67|                        StreamStatsView(player: player.player)
    68|                            .padding(10)
    69|                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    70|                            .allowsHitTesting(false)
    71|                    }
    72|                }
    73|                .padding([.horizontal, .top])
    74|
    75|                // EPG info bar
    76|                if let entry = nowPlaying {
    77|                    EPGInfoBar(current: entry, next: nextUp, showTimeline: $showTimeline)
    78|                        .padding(.horizontal)
    79|                        .padding(.top, 4)
    80|
    81|                    // EPG Timeline — collapsible
    82|                    if showTimeline && !allEPGEntries.isEmpty {
    83|                        EPGTimelineView(entries: allEPGEntries, channelID: player.currentChannel?.epgId ?? player.currentChannel?.name ?? "")
    84|                            .padding(.horizontal, 4)
    85|                            .transition(.move(edge: .top).combined(with: .opacity))
    86|                    }
    87|                }
    88|
    89|                Spacer(minLength: 8)
    90|
    91|                // Controls
    92|                PlayerControls(player: player, showStats: $showStats)
    93|                    .padding(.horizontal)
    94|                    .padding(.bottom)
    95|            }
    96|
    97|            // PIN Lock Overlay
    98|            if showPINLock, let channel = blockedChannel, let reason = blockReason {
    99|                PINLockView(
   100|                    reason: reason,
   101|                    service: parentalService,
   102|                    onUnlock: {
   103|                        showPINLock = false
   104|                        blockedChannel = nil
   105|                        blockReason = nil
   106|                    },
   107|                    onCancel: {
   108|                        showPINLock = false
   109|                        blockedChannel = nil
   110|                        blockReason = nil
   111|                        player.stop()
   112|                    }
   113|                )
   114|            }
   115|        }
   116|        .onChange(of: player.currentChannel) { _, newChannel in
   117|            // Check parental controls
   118|            if let channel = newChannel {
   119|                if !parentalService.isChannelAllowed(channel) {
   120|                    blockedChannel = channel
   121|                    blockReason = parentalService.getBlockReason(for: channel)
   122|                    showPINLock = true
   123|                    player.pause()
   124|                    return
   125|                }
   126|            }
   127|
   128|            // Cancel any in-flight EPG fetch (debounce for rapid zap/prev/next)
   129|            epgFetchTask?.cancel()
   130|            epgFetchTask = Task {
   131|                // 250ms debounce — ignore if channel changes again quickly
   132|                try? await Task.sleep(for: .milliseconds(250))
   133|                guard !Task.isCancelled else { return }
   134|                await loadEPG(for: newChannel)
   135|            }
   136|            // Auto-search subtitles: use channel name (EPG title loaded async)
   137|            if let name = newChannel?.name {
   138|                subtitleStore.search(for: name)
   139|            }
   140|        }
   141|        // Subtitle cue update ticker (0.5s)
   142|        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
   143|            let t = player.player.currentTime().seconds
   144|            if t.isFinite { subtitleStore.updateCurrentCue(time: t) }
   145|        }
   146|        // Keyboard shortcuts (macOS only — iOS/tvOS use focus-based controls)
   147|        #if os(macOS)
   148|        .onKeyPress(.space) {
   149|            player.togglePlayPause()
   150|            return .handled
   151|        }
   152|        .onKeyPress(.leftArrow) {
   153|            player.playPrevious()
   154|            return .handled
   155|        }
   156|        .onKeyPress(.rightArrow) {
   157|            player.playNext()
   158|            return .handled
   159|        }
   160|        #endif
   161|    }
   162|
   163|    @ViewBuilder
   164|    private var stateOverlay: some View {
   165|        switch player.state {
   166|        case .loading:
   167|            VStack(spacing: 10) {
   168|                ProgressView()
   169|                    .scaleEffect(1.5)
   170|                    .tint(.white)
   171|                if player.retryCount > 0 {
   172|                    Text("Buffering… (\(player.retryCount)/\(player.maxRetries))")
   173|                        .font(.system(size: 12, weight: .medium))
   174|                        .foregroundStyle(.white.opacity(0.8))
   175|                }
   176|            }
   177|            .padding(16)
   178|            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
   179|        case .error(let msg):
   180|            ErrorRetryView(message: msg) {
   181|                if let channel = player.currentChannel {
   182|                    Task { @MainActor in
   183|                        player.play(channel)
   184|                    }
   185|                }
   186|            }
   187|        default:
   188|            EmptyView()
   189|        }
   190|    }
   191|
   192|    private func loadEPG(for channel: Channel?) async {
   193|        guard let channel else {
   194|            nowPlaying = nil
   195|            nextUp = nil
   196|            allEPGEntries = []
   197|            return
   198|        }
   199|        let cid = channel.epgId ?? channel.name
   200|        let now = Date()
   201|        nowPlaying = await epgStore.service.nowPlaying(for: cid, at: now)
   202|        nextUp    = await epgStore.service.nextUp(for: cid, at: now)
   203|        allEPGEntries = await epgStore.service.entries(for: cid)
   204|    }
   205|
   206|    @MainActor
   207|    private func showEPGOverlayWithAutoHide() {
   208|        // Cancel any existing hide task
   209|        overlayHideTask?.cancel()
   210|
   211|        // Show overlay
   212|        withAnimation(.easeInOut(duration: 0.25)) {
   213|            showEPGOverlay = true
   214|        }
   215|
   216|        // Schedule auto-hide after 3 seconds
   217|        overlayHideTask = Task {
   218|            try? await Task.sleep(for: .seconds(3))
   219|            guard !Task.isCancelled else { return }
   220|            withAnimation(.easeInOut(duration: 0.25)) {
   221|                showEPGOverlay = false
   222|            }
   223|        }
   224|    }
   225|}
   226|
   227|// MARK: - EPGTimelineOverlay
   228|
   229|@MainActor
   230|struct EPGTimelineOverlay: View {
   231|    let current: EPGEntry
   232|    let next: EPGEntry?
   233|
   234|    private static let timeFormatter: DateFormatter = {
   235|        let f = DateFormatter()
   236|        f.dateStyle = .none
   237|        f.timeStyle = .short
   238|        return f
   239|    }()
   240|
   241|    private var timeRemaining: String {
   242|        let remaining = current.end.timeIntervalSince(Date())
   243|        guard remaining > 0 else { return "Ending soon" }
   244|        let minutes = Int(remaining / 60)
   245|        if minutes < 60 {
   246|            return "\(minutes) min left"
   247|        } else {
   248|            let hours = minutes / 60
   249|            let mins = minutes % 60
   250|            return "\(hours)h \(mins)m left"
   251|        }
   252|    }
   253|
   254|    var body: some View {
   255|        VStack(alignment: .leading, spacing: 8) {
   256|            // Current program
   257|            HStack(spacing: 8) {
   258|                VStack(alignment: .leading, spacing: 2) {
   259|                    Text(current.title)
   260|                        .font(.system(size: 14, weight: .semibold))
   261|                        .foregroundStyle(.white)
   262|                        .lineLimit(1)
   263|                    Text(timeRemaining)
   264|                        .font(.system(size: 11, weight: .medium))
   265|                        .foregroundStyle(.white.opacity(0.8))
   266|                }
   267|                Spacer()
   268|            }
   269|
   270|            // Progress bar
   271|            EPGOverlayProgressBar(entry: current)
   272|
   273|            // Next program
   274|            if let next {
   275|                HStack(spacing: 6) {
   276|                    Text("NEXT:")
   277|                        .font(.system(size: 10, weight: .bold))
   278|                        .foregroundStyle(.white.opacity(0.6))
   279|                    Text(next.title)
   280|                        .font(.system(size: 11, weight: .medium))
   281|                        .foregroundStyle(.white.opacity(0.8))
   282|                        .lineLimit(1)
   283|                    Text("·")
   284|                        .foregroundStyle(.white.opacity(0.5))
   285|                    Text(Self.timeFormatter.string(from: next.start))
   286|                        .font(.system(size: 11, weight: .medium))
   287|                        .foregroundStyle(.white.opacity(0.8))
   288|                }
   289|            }
   290|        }
   291|        .padding(12)
   292|        .background(
   293|            RoundedRectangle(cornerRadius: 8)
   294|                .fill(.black.opacity(0.75))
   295|                .background(.ultraThinMaterial.opacity(0.5))
   296|                .clipShape(RoundedRectangle(cornerRadius: 8))
   297|        )
   298|        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
   299|    }
   300|}
   301|
   302|// MARK: - EPGOverlayProgressBar
   303|
   304|struct EPGOverlayProgressBar: View {
   305|    let entry: EPGEntry
   306|    @State private var progress: Double = 0
   307|
   308|    var body: some View {
   309|        GeometryReader { geo in
   310|            ZStack(alignment: .leading) {
   311|                Capsule()
   312|                    .fill(.white.opacity(0.2))
   313|                    .frame(height: 3)
   314|                Capsule()
   315|                    .fill(.white)
   316|                    .frame(width: geo.size.width * progress, height: 3)
   317|            }
   318|        }
   319|        .frame(height: 3)
   320|        .onAppear { progress = entry.progress() }
   321|        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
   322|            withAnimation(.linear(duration: 1)) { progress = entry.progress() }
   323|        }
   324|    }
   325|}
   326|
   327|// MARK: - EPGInfoBar
   328|
   329|struct EPGInfoBar: View {
   330|    let current: EPGEntry
   331|    let next: EPGEntry?
   332|    @Binding var showTimeline: Bool
   333|
   334|    private static let timeFormatter: DateFormatter = {
   335|        let f = DateFormatter()
   336|        f.dateStyle = .none
   337|        f.timeStyle = .short
   338|        return f
   339|    }()
   340|
   341|    var body: some View {
   342|        VStack(alignment: .leading, spacing: 6) {
   343|            HStack(alignment: .top) {
   344|                VStack(alignment: .leading, spacing: 2) {
   345|                    Label {
   346|                        Text(current.title)
   347|                            .font(.aetherHeadline)
   348|                            .foregroundStyle(Color.aetherText)
   349|                    } icon: {
   350|                        Text("NOW")
   351|                            .font(.system(size: 9, weight: .bold))
   352|                            .foregroundStyle(.white)
   353|                            .padding(.horizontal, 5)
   354|                            .padding(.vertical, 2)
   355|                            .background(Color.aetherPrimary, in: RoundedRectangle(cornerRadius: 4))
   356|                    }
   357|                    Text("\(Self.timeFormatter.string(from: current.start)) – \(Self.timeFormatter.string(from: current.end))")
   358|                        .font(.aetherCaption)
   359|                        .foregroundStyle(.secondary)
   360|                }
   361|                Spacer()
   362|                // Timeline toggle button
   363|                Button {
   364|                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
   365|                        showTimeline.toggle()
   366|                    }
   367|                } label: {
   368|                    HStack(spacing: 4) {
   369|                        Image(systemName: "calendar")
   370|                            .font(.system(size: 11, weight: .medium))
   371|                        Image(systemName: "chevron.down")
   372|                            .font(.system(size: 9, weight: .semibold))
   373|                            .rotationEffect(.degrees(showTimeline ? 180 : 0))
   374|                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showTimeline)
   375|                    }
   376|                    .foregroundStyle(showTimeline ? Color.accentColor : Color.secondary)
   377|                    .padding(.horizontal, 8)
   378|                    .padding(.vertical, 5)
   379|                    .background(
   380|                        showTimeline
   381|                            ? Color.accentColor.opacity(0.15)
   382|                            : Color.secondary.opacity(0.1),
   383|                        in: Capsule()
   384|                    )
   385|                }
   386|                .buttonStyle(.plain)
   387|                .help(showTimeline ? "Hide EPG Timeline" : "Show EPG Timeline")
   388|
   389|                if let desc = current.description {
   390|                    Text(desc)
   391|                        .font(.aetherCaption)
   392|                        .foregroundStyle(.secondary)
   393|                        .lineLimit(2)
   394|                        .multilineTextAlignment(.trailing)
   395|                        .frame(maxWidth: 200)
   396|                }
   397|            }
   398|
   399|            EPGProgressBarView(entry: current)
   400|
   401|            if let next {
   402|                HStack(spacing: 4) {
   403|                    Text("NEXT")
   404|                        .font(.system(size: 9, weight: .semibold))
   405|                        .foregroundStyle(.secondary)
   406|                    Text(next.title)
   407|                        .font(.aetherCaption)
   408|                        .foregroundStyle(.secondary)
   409|                    Text("·")
   410|                        .foregroundStyle(.secondary)
   411|                    Text(Self.timeFormatter.string(from: next.start))
   412|                        .font(.aetherCaption)
   413|                        .foregroundStyle(.secondary)
   414|                }
   415|            }
   416|        }
   417|        .padding(10)
   418|        .background(Color.aetherSurface, in: RoundedRectangle(cornerRadius: 10))
   419|    }
   420|}
   421|
   422|// MARK: - EPGProgressBarView
   423|
   424|struct EPGProgressBarView: View {
   425|    let entry: EPGEntry
   426|    @State private var progress: Double = 0
   427|
   428|    var body: some View {
   429|        GeometryReader { geo in
   430|            ZStack(alignment: .leading) {
   431|                Capsule().fill(Color.aetherSurface).frame(height: 4)
   432|                Capsule().fill(Color.aetherPrimary)
   433|                    .frame(width: geo.size.width * progress, height: 4)
   434|            }
   435|        }
   436|        .frame(height: 4)
   437|        .onAppear { progress = entry.progress() }
   438|        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
   439|            withAnimation(.linear(duration: 1)) { progress = entry.progress() }
   440|        }
   441|    }
   442|}
   443|
   444|// MARK: - VideoPlayerLayer (AVKit, fullscreen + PiP)
   445|
   446|struct VideoPlayerLayer: NSViewRepresentable {
   447|    let avPlayer: AVPlayer
   448|    /// Weak reference so the coordinator can report PiP state changes back.
   449|    weak var playerCore: PlayerCore?
   450|
   451|    func makeCoordinator() -> Coordinator {
   452|        Coordinator(playerCore: playerCore)
   453|    }
   454|
   455|    func makeNSView(context: Context) -> AVPlayerView {
   456|        let view = AVPlayerView()
   457|        view.player = avPlayer
   458|        // Show native controls including fullscreen and PiP buttons
   459|        view.controlsStyle = .floating
   460|        view.allowsPictureInPicturePlayback = true
   461|        view.showsFullScreenToggleButton = true
   462|        view.pictureInPictureDelegate = context.coordinator
   463|
   464|        // Listen for PiP toggle notification
   465|        context.coordinator.pipObserver = NotificationCenter.default.addObserver(
   466|            forName: .togglePiP,
   467|            object: nil,
   468|            queue: .main
   469|        ) { [weak view, weak playerCore] _ in
   470|            Task { @MainActor in
   471|                guard let view = view, view.allowsPictureInPicturePlayback else { return }
   472|                if playerCore?.isPiPActive == true {
   473|                    // Exit PiP by setting player to nil temporarily
   474|                    let player = view.player
   475|                    view.player = nil
   476|                    view.player = player
   477|                } else {
   478|                    // Enter PiP - handled by system controls
   479|                }
   480|            }
   481|        }
   482|
   483|        return view
   484|    }
   485|
   486|    func updateNSView(_ nsView: AVPlayerView, context: Context) {
   487|        if nsView.player !== avPlayer { nsView.player = avPlayer }
   488|        context.coordinator.playerCore = playerCore
   489|    }
   490|
   491|    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
   492|        if let observer = coordinator.pipObserver {
   493|            NotificationCenter.default.removeObserver(observer)
   494|        }
   495|    }
   496|
   497|    // MARK: - Coordinator
   498|
   499|    @MainActor
   500|    final class Coordinator: NSObject, AVPlayerViewPictureInPictureDelegate {
   501|