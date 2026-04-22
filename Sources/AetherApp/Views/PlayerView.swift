import SwiftUI
import SwiftData
import AVKit
import AetherCore
import AetherUI

/// Detail pane: AVPlayer video + transport controls + EPG info bar + timeline.
struct PlayerView: View {
    @Environment(EPGStore.self) private var epgStore
    @Environment(SleepTimerService.self) private var sleepTimer
    @Environment(SubtitleStore.self) private var subtitleStore
    @Environment(ParentalControlService.self) private var parentalService

    @Bindable var player: PlayerCore

    @State private var nowPlaying: EPGEntry?
    @State private var nextUp: EPGEntry?
    /// All EPG entries for the current channel (may span multiple days).
    @State private var allEPGEntries: [EPGEntry] = []
    @State private var showStats = false
    @State private var showTimeline = false
    /// Cancellation token for in-flight EPG fetch (debounce for rapid channel changes).
    @State private var epgFetchTask: Task<Void, Never>?
    /// EPG timeline overlay visibility (hover/interaction)
    @State private var showEPGOverlay = false
    /// Auto-hide timer for EPG overlay
    @State private var overlayHideTask: Task<Void, Never>?
    /// Parental control lock state
    @State private var showPINLock = false
    @State private var blockedChannel: Channel?
    @State private var blockReason: String?
    @State private var showControls = true
    @State private var controlsHideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.aetherBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Video layer
                ZStack(alignment: .bottom) {
                    VideoPlayerLayer(avPlayer: player.player, playerCore: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .bottomLeading) {
                            stateOverlay
                                .padding([.horizontal, .bottom], 20)
                        }
                        .overlay(alignment: .bottom) {
                            // EPG Timeline Overlay (bottom, auto-hide)
                            if showEPGOverlay, let current = nowPlaying {
                                EPGTimelineOverlay(current: current, next: nextUp)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 16)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            Group {
                                if let channel = player.currentChannel {
                                    channelInfoBadge(channel: channel)
                                }
                            }
                            .opacity(showControls ? 1 : 0)
                            .animation(.easeInOut(duration: 0.3), value: showControls)
                            .padding([.top, .leading], 16)
                        }
                        .overlay(alignment: .topTrailing) {
                            Button { player.startPiP() } label: {
                                Image(systemName: "pip.enter")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(.black.opacity(0.5), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .opacity(showControls ? 1 : 0)
                            .animation(.easeInOut(duration: 0.3), value: showControls)
                            .padding([.top, .trailing], 12)
                            .disabled(player.currentChannel == nil)
                        }
                        .onHover { hovering in
                            if hovering {
                                showEPGOverlayWithAutoHide()
                                showControlsWithAutoHide()
                            }
                        }
                        .onTapGesture(count: 1) {
                            showControlsWithAutoHide()
                        }
                        .contextMenu {
                            if let url = player.currentChannel?.streamURL {
                                Button("Copy Stream URL") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                }
                                Divider()
                            }
                            Button(showStats ? "Hide Stream Stats" : "Show Stream Stats") {
                                showStats.toggle()
                            }
                            Divider()
                            Menu("Quality") {
                                ForEach(player.qualityPresets) { preset in
                                    Button {
                                        player.selectedQuality = preset
                                    } label: {
                                        if player.selectedQuality.id == preset.id {
                                            Label(preset.label, systemImage: "checkmark")
                                        } else {
                                            Text(preset.label)
                                        }
                                    }
                                }
                            }
                            if !player.availableSubtitleOptions.isEmpty {
                                Divider()
                                Menu("Subtitles") {
                                    Button {
                                        player.selectSubtitleOption(nil)
                                    } label: {
                                        if player.selectedSubtitleOption == nil {
                                            Label("Off", systemImage: "checkmark")
                                        } else {
                                            Text("Off")
                                        }
                                    }
                                    ForEach(player.availableSubtitleOptions, id: \.self) { option in
                                        Button {
                                            player.selectSubtitleOption(option)
                                        } label: {
                                            if option == player.selectedSubtitleOption {
                                                Label(option.displayName, systemImage: "checkmark")
                                            } else {
                                                Text(option.displayName)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        #if os(macOS)
                        .onScrollWheel { event in
                            // Scroll wheel up/down → volume ±5%
                            let delta = Float(event.scrollingDeltaY) * 0.005
                            player.adjustVolume(delta: -delta)
                        }
                        #endif

                    // Subtitle overlay — non-interactive
                    SubtitleOverlayView(store: subtitleStore)

                    // Stream stats HUD — top-trailing corner
                    if showStats {
                        StreamStatsView(player: player.player)
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .allowsHitTesting(false)
                    }
                }
                .padding([.horizontal, .top])

                // EPG info bar
                if let entry = nowPlaying {
                    EPGInfoBar(current: entry, next: nextUp, showTimeline: $showTimeline)
                        .padding(.horizontal)
                        .padding(.top, 4)

                    // EPG Timeline — collapsible
                    if showTimeline && !allEPGEntries.isEmpty {
                        EPGTimelineView(entries: allEPGEntries, channelID: player.currentChannel?.epgId ?? player.currentChannel?.name ?? "", channelName: player.currentChannel?.name ?? "")
                            .padding(.horizontal, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                Spacer(minLength: 8)

                // Controls — auto-hide after 3s of inactivity, shown on hover/tap
                PlayerControlsView(player: player, showStats: $showStats)
                    .padding(.horizontal)
                    .padding(.bottom)
                    .opacity(showControls ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: showControls)
            }

            // Stream error banner — auto-dismissing, appears at top of player
            if let banner = player.streamErrorBanner {
                VStack {
                    Text(banner)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 16)
                .animation(.easeInOut(duration: 0.3), value: player.streamErrorBanner)
            }

            // Hidden Cmd+I shortcut: toggle stream stats HUD
            Button("") { showStats.toggle() }
                .keyboardShortcut("i", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)

            // PIN Lock Overlay
            if showPINLock, blockedChannel != nil, let reason = blockReason {
                PINLockView(
                    reason: reason,
                    service: parentalService,
                    onUnlock: {
                        showPINLock = false
                        blockedChannel = nil
                        blockReason = nil
                    },
                    onCancel: {
                        showPINLock = false
                        blockedChannel = nil
                        blockReason = nil
                        player.stop()
                    }
                )
            }
        }
        .onChange(of: player.currentChannel) { _, newChannel in
            // Check parental controls
            if let channel = newChannel {
                if !parentalService.isChannelAllowed(channel) {
                    blockedChannel = channel
                    blockReason = parentalService.getBlockReason(for: channel)
                    showPINLock = true
                    player.pause()
                    return
                }
            }

            // Cancel any in-flight EPG fetch (debounce for rapid zap/prev/next)
            epgFetchTask?.cancel()
            epgFetchTask = Task {
                // 250ms debounce — ignore if channel changes again quickly
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await loadEPG(for: newChannel)
            }
            // Auto-search subtitles: use channel name (EPG title loaded async)
            if let name = newChannel?.name {
                subtitleStore.search(for: name)
            }
        }
        // Subtitle cue update ticker (0.5s)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            let t = player.player.currentTime().seconds
            if t.isFinite { subtitleStore.updateCurrentCue(time: t) }
        }
        // Keyboard shortcuts (macOS only — iOS/tvOS use focus-based controls)
        #if os(macOS)
        .onKeyPress(.space) {
            player.togglePlayPause()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if player.isLiveStream { player.playPrevious() } else { player.seek(by: -10) }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if player.isLiveStream { player.playNext() } else { player.seek(by: 10) }
            return .handled
        }
        #endif
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch player.state {
        case .loading:
            VStack(spacing: 10) {
                if let logoURL = player.currentChannel?.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                PulsingCircle()
                if player.retryCount > 0 {
                    Text("Buffering… (\(player.retryCount)/\(player.maxRetries))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        case .error(let msg):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
                Button {
                    if let channel = player.currentChannel {
                        Task { @MainActor in
                            player.play(channel)
                        }
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func channelInfoBadge(channel: Channel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(channel.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let title = nowPlaying?.title {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func loadEPG(for channel: Channel?) async {
        guard let channel else {
            nowPlaying = nil
            nextUp = nil
            allEPGEntries = []
            return
        }
        let cid = channel.epgId ?? channel.name
        let now = Date()
        nowPlaying = await epgStore.service.nowPlaying(for: cid, at: now)
        nextUp    = await epgStore.service.nextUp(for: cid, at: now)
        allEPGEntries = await epgStore.service.entries(for: cid)
    }

    @MainActor
    private func showControlsWithAutoHide() {
        controlsHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
        controlsHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showControls = false }
        }
    }

    @MainActor
    private func showEPGOverlayWithAutoHide() {
        // Cancel any existing hide task
        overlayHideTask?.cancel()

        // Show overlay
        withAnimation(.easeInOut(duration: 0.25)) {
            showEPGOverlay = true
        }

        // Schedule auto-hide after 3 seconds
        overlayHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showEPGOverlay = false
            }
        }
    }
}

// MARK: - EPGTimelineOverlay

@MainActor
struct EPGTimelineOverlay: View {
    let current: EPGEntry
    let next: EPGEntry?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var timeRemaining: String {
        let remaining = current.end.timeIntervalSince(Date())
        guard remaining > 0 else { return "Ending soon" }
        let minutes = Int(remaining / 60)
        if minutes < 60 {
            return "\(minutes) min left"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m left"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current program
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(timeRemaining)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
            }

            // Progress bar
            EPGOverlayProgressBar(entry: current)

            // Next program
            if let next {
                HStack(spacing: 6) {
                    Text("NEXT:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(next.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(Self.timeFormatter.string(from: next.start))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.75))
                .background(.ultraThinMaterial.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

// MARK: - EPGOverlayProgressBar

struct EPGOverlayProgressBar: View {
    let entry: EPGEntry
    @State private var progress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: 3)
                Capsule()
                    .fill(.white)
                    .frame(width: geo.size.width * progress, height: 3)
            }
        }
        .frame(height: 3)
        .onAppear { progress = entry.progress() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.linear(duration: 1)) { progress = entry.progress() }
        }
    }
}

// MARK: - EPGInfoBar

struct EPGInfoBar: View {
    let current: EPGEntry
    let next: EPGEntry?
    @Binding var showTimeline: Bool

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(current.title)
                            .font(.aetherHeadline)
                            .foregroundStyle(Color.aetherText)
                    } icon: {
                        Text("NOW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.aetherPrimary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text("\(Self.timeFormatter.string(from: current.start)) – \(Self.timeFormatter.string(from: current.end))")
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Timeline toggle button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        showTimeline.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(showTimeline ? 180 : 0))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showTimeline)
                    }
                    .foregroundStyle(showTimeline ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        showTimeline
                            ? Color.accentColor.opacity(0.15)
                            : Color.secondary.opacity(0.1),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .help(showTimeline ? "Hide EPG Timeline" : "Show EPG Timeline")

                if let desc = current.description {
                    Text(desc)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }
            }

            EPGProgressBarView(entry: current)

            if let next {
                HStack(spacing: 4) {
                    Text("NEXT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(next.title)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(Self.timeFormatter.string(from: next.start))
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.aetherSurface, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - EPGProgressBarView

struct EPGProgressBarView: View {
    let entry: EPGEntry
    @State private var progress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.aetherSurface).frame(height: 4)
                Capsule().fill(Color.aetherPrimary)
                    .frame(width: geo.size.width * progress, height: 4)
            }
        }
        .frame(height: 4)
        .onAppear { progress = entry.progress() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.linear(duration: 1)) { progress = entry.progress() }
        }
    }
}

// MARK: - VideoPlayerLayer (AVKit, fullscreen + PiP)

struct VideoPlayerLayer: NSViewRepresentable {
    let avPlayer: AVPlayer
    /// Weak reference so the coordinator can report PiP state changes back.
    weak var playerCore: PlayerCore?

    func makeCoordinator() -> Coordinator {
        Coordinator(playerCore: playerCore)
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = avPlayer
        view.controlsStyle = .none
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        view.pictureInPictureDelegate = context.coordinator
        context.coordinator.playerView = view

        // Double-click to toggle fullscreen
        let doubleClick = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick(_:))
        )
        doubleClick.numberOfClicksRequired = 2
        view.addGestureRecognizer(doubleClick)

        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== avPlayer { nsView.player = avPlayer }
        context.coordinator.playerCore = playerCore
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {}

    // MARK: - Coordinator (AVKit)

    final class Coordinator: NSObject, AVPlayerViewPictureInPictureDelegate {
        weak var playerCore: PlayerCore?
        weak var playerView: AVPlayerView?

        init(playerCore: PlayerCore?) {
            self.playerCore = playerCore
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePiPStartRequest),
                name: .pipStartRequested,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handlePiPStartRequest() {
            // AVPlayerView manages PiP via its built-in overlay controls.
            // Programmatic PiP activation requires AVPictureInPictureController;
            // AVPlayerView does not expose a public startPictureInPicture() method.
            // The user can activate PiP via the floating controls overlay.
        }

        @objc func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
            gesture.view?.window?.toggleFullScreen(nil)
        }

        nonisolated func playerViewWillStartPicture(inPicture playerView: AVPlayerView) {}
        nonisolated func playerViewDidStartPicture(inPicture playerView: AVPlayerView) {
            Task { @MainActor [weak self] in self?.playerCore?.setPiPActive(true) }
        }
        nonisolated func playerViewWillStopPicture(inPicture playerView: AVPlayerView) {}
        nonisolated func playerViewDidStopPicture(inPicture playerView: AVPlayerView) {
            Task { @MainActor [weak self] in self?.playerCore?.setPiPActive(false) }
        }
    }
}

// MARK: - PulsingCircle

struct PulsingCircle: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 52, height: 52)
                .scaleEffect(pulsing ? 1.7 : 1.0)
                .opacity(pulsing ? 0 : 1)
                .animation(
                    .easeOut(duration: 0.9).repeatForever(autoreverses: false),
                    value: pulsing
                )
            Circle()
                .fill(.white.opacity(0.65))
                .frame(width: 28, height: 28)
        }
        .onAppear { pulsing = true }
    }
}
