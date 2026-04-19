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
                        .onHover { hovering in
                            if hovering {
                                showEPGOverlayWithAutoHide()
                            }
                        }

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
                        EPGTimelineView(entries: allEPGEntries, channelID: player.currentChannel?.epgId ?? player.currentChannel?.name ?? "")
                            .padding(.horizontal, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                Spacer(minLength: 8)

                // Controls
                PlayerControlsView(player: player, showStats: $showStats)
                    .padding(.horizontal)
                    .padding(.bottom)
            }

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
            player.playPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            player.playNext()
            return .handled
        }
        #endif
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch player.state {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
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
                    .font(.system(size: 48))
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    if let channel = player.currentChannel {
                        Task { @MainActor in
                            player.play(channel)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        default:
            EmptyView()
        }
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
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = avPlayer
        // Show native controls including fullscreen and PiP buttons
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        view.pictureInPictureDelegate = context.coordinator

        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== avPlayer { nsView.player = avPlayer }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, AVPlayerViewPictureInPictureDelegate {
        nonisolated func playerViewWillStartPicture(inPicture playerView: AVPlayerView) {}
        nonisolated func playerViewDidStartPicture(inPicture playerView: AVPlayerView) {}
        nonisolated func playerViewWillStopPicture(inPicture playerView: AVPlayerView) {}
        nonisolated func playerViewDidStopPicture(inPicture playerView: AVPlayerView) {}
    }
}
