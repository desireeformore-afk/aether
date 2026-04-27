import SwiftUI
import SwiftData
import AetherCore
import AetherUI

/// Detail pane: VLC video + transport controls + EPG info bar + timeline.
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
            // Professional black backdrop for the player
            Color.black.ignoresSafeArea()

            // Video takes full available space — VLC renders directly into NSView
            VLCVideoView(player: player)
                .ignoresSafeArea()
                .onHover { hovering in
                    if hovering { showHUDWithAutoHide() }
                }
                .onTapGesture(count: 1) { showHUDWithAutoHide() }
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
                    if !player.availableSubtitleTracks.isEmpty {
                        Divider()
                        Menu("Subtitles") {
                            Button {
                                player.selectSubtitleTrack(nil)
                            } label: {
                                if player.selectedSubtitleTrackID == -1 {
                                    Label("Off", systemImage: "checkmark")
                                } else {
                                    Text("Off")
                                }
                            }
                            ForEach(player.availableSubtitleTracks) { track in
                                Button {
                                    player.selectSubtitleTrack(track)
                                } label: {
                                    if player.selectedSubtitleTrackID == track.id {
                                        Label(track.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(track.displayName)
                                    }
                                }
                            }
                        }
                    }
                    if !subtitleStore.tracks.isEmpty {
                        Divider()
                        Menu("OpenSubtitles") {
                            Button("None") { subtitleStore.clear() }
                            ForEach(subtitleStore.tracks) { track in
                                Button("\(track.language) — \(track.languageName)") {
                                    subtitleStore.load(track: track)
                                }
                            }
                        }
                    }
                }
                #if os(macOS)
                .onScrollWheel { event in
                    let delta = Float(event.scrollingDeltaY) * 0.005
                    player.adjustVolume(delta: -delta)
                }
                #endif

            // Subtitle overlay — non-interactive
            SubtitleOverlayView(store: subtitleStore)

            // Top Layer: Badges, Stats & Error Banner
            VStack {
                HStack(alignment: .top, spacing: 12) {
                    // Close Player Button
                    Button(action: { player.stop() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .opacity(showControls ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: showControls)

                    // Top Left Badge
                    if let channel = player.currentChannel {
                        channelInfoBadge(channel: channel)
                            .opacity(showControls ? 1 : 0)
                            .animation(.easeInOut(duration: 0.3), value: showControls)
                    }
                    
                    Spacer()
                    
                    // Top Right Controls (PiP, Stats)
                    HStack(alignment: .top, spacing: 12) {
                        if showStats {
                            StreamStatsView(player: player)
                                .allowsHitTesting(false)
                        }
                        
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
                        .disabled(player.currentChannel == nil)
                    }
                }
                .padding([.top, .horizontal], 16)
                
                // Error Banner
                if let banner = player.streamErrorBanner {
                    Text(banner)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 16)
                }
                
                Spacer() // Push the rest to bottom
                
                // Loading Overlay (Centered)
                if case .loading = player.state {
                    stateOverlay
                } else if case .error(_) = player.state {
                    stateOverlay
                }

                Spacer()
                
                // Bottom Floating HUD Area
                VStack(spacing: 8) {
                    if showEPGOverlay, let current = nowPlaying {
                        EPGTimelineOverlay(current: current, next: nextUp)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    if let entry = nowPlaying {
                        EPGInfoBar(current: entry, next: nextUp, showTimeline: $showTimeline)
                        if showTimeline && !allEPGEntries.isEmpty {
                            EPGTimelineView(entries: allEPGEntries, channelID: player.currentChannel?.epgId ?? player.currentChannel?.name ?? "", channelName: player.currentChannel?.name ?? "")
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    
                    PlayerControlsView(player: player, showStats: $showStats)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .opacity(showControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: showControls)
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
            let t = player.currentTime
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
            Text(VODNormalizer.extractTagsAndClean(channel.name).cleanTitle)
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
    private func showHUDWithAutoHide() {
        controlsHideTask?.cancel()
        overlayHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls = true
            showEPGOverlay = true
        }
        let task = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
                showEPGOverlay = false
            }
        }
        controlsHideTask = task
        overlayHideTask = task
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

// VideoPlayerLayer removed — replaced by VLCVideoView (see VLCVideoView.swift)

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
