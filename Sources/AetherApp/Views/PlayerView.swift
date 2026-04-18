import SwiftUI
import SwiftData
import AVKit
import AetherCore
import AetherUI

/// Detail pane: AVPlayer video + transport controls + EPG info bar + timeline.
struct PlayerView: View {
    @EnvironmentObject private var epgStore: EPGStore
    @EnvironmentObject private var sleepTimer: SleepTimerService
    @EnvironmentObject private var subtitleStore: SubtitleStore

    @ObservedObject var player: PlayerCore

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
                PlayerControls(player: player, showStats: $showStats)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
        .onChange(of: player.currentChannel) { _, newChannel in
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
            ErrorRetryView(message: msg) {
                if let channel = player.currentChannel {
                    Task { @MainActor in
                        player.play(channel)
                    }
                }
            }
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
        Coordinator(playerCore: playerCore)
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
        context.coordinator.playerCore = playerCore
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewPictureInPictureDelegate {
        weak var playerCore: PlayerCore?

        init(playerCore: PlayerCore?) {
            self.playerCore = playerCore
        }

        nonisolated func playerViewWillStartPicture(inPicture playerView: AVPlayerView) {
            Task { @MainActor [weak self] in self?.playerCore?.setPiPActive(true) }
        }

        nonisolated func playerViewWillStopPicture(inPicture playerView: AVPlayerView) {
            Task { @MainActor [weak self] in self?.playerCore?.setPiPActive(false) }
        }
    }
}

// MARK: - PlayerControls

struct PlayerControls: View {
    @ObservedObject var player: PlayerCore
    @EnvironmentObject private var sleepTimer: SleepTimerService
    @Environment(\.modelContext) private var modelContext
    @Binding var showStats: Bool

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentChannel?.name ?? "No channel selected")
                    .font(.aetherBody)
                    .foregroundStyle(Color.aetherText)
                    .lineLimit(1)
                if let group = player.currentChannel?.groupTitle, !group.isEmpty {
                    Text(group)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            // Previous channel
            Button(action: { player.playPrevious() }) {
                Image(systemName: "backward.fill")
                    .font(.title3)
                    .foregroundStyle(Color.aetherText)
            }
            .buttonStyle(.plain)
            .disabled(player.currentChannel == nil)
            .help("Previous Channel  ←")
            .keyboardShortcut(.leftArrow, modifiers: [])

            // Play / Pause
            Button(action: { player.togglePlayPause() }) {
                Image(systemName: playPauseIcon)
                    .font(.title2)
                    .foregroundStyle(Color.aetherPrimary)
            }
            .buttonStyle(.plain)
            .disabled(player.currentChannel == nil)
            .help(isPlaying ? "Pause  Space" : "Play  Space")
            .keyboardShortcut(" ", modifiers: [])

            // Next channel
            Button(action: { player.playNext() }) {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(Color.aetherText)
            }
            .buttonStyle(.plain)
            .disabled(player.currentChannel == nil)
            .help("Next Channel  →")
            .keyboardShortcut(.rightArrow, modifiers: [])

            // Stop
            Button(action: { player.stop() }) {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .foregroundStyle(player.currentChannel == nil ? .secondary : Color.aetherText)
            }
            .buttonStyle(.plain)
            .disabled(player.currentChannel == nil)
            .help("Stop")

            Divider().frame(height: 24)

            // Stream quality picker
            Menu {
                ForEach(player.qualityPresets) { preset in
                    Button(action: { player.selectedQuality = preset }) {
                        HStack {
                            Text(preset.label)
                            if player.selectedQuality == preset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "dial.medium")
                        .font(.title3)
                    Text(player.selectedQuality.label)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.aetherText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(player.currentChannel == nil)
            .help("Stream Quality")

            Divider().frame(height: 24)

            // Mute
            Button(action: { player.toggleMute() }) {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(Color.aetherText)
            }
            .buttonStyle(.plain)
            .help(player.isMuted ? "Unmute  M" : "Mute  M")
            .keyboardShortcut("m", modifiers: [])

            // Volume slider
            Slider(value: Binding(
                get: { Double(player.volume) },
                set: { player.setVolume(Float($0)) }
            ), in: 0...1)
            .frame(width: 80)
            .disabled(player.isMuted)

            Divider().frame(height: 24)

            // Sleep timer
            SleepTimerButton()

            Divider().frame(height: 24)

            // Subtitle picker
            SubtitlePickerButton()

            Divider().frame(height: 24)

            // Stream stats toggle
            Button(action: { showStats.toggle() }) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3)
                    .foregroundStyle(showStats ? Color.aetherAccent : Color.aetherText)
            }
            .buttonStyle(.plain)
            .help(showStats ? "Hide Stream Stats" : "Show Stream Stats")

            Divider().frame(height: 24)

            // Favorite toggle
            FavoriteButton(channel: player.currentChannel)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var isPlaying: Bool { player.state == .playing }
    private var playPauseIcon: String { isPlaying ? "pause.fill" : "play.fill" }
}

// MARK: - SubtitlePickerButton

fileprivate struct SubtitlePickerButton: View {
    @EnvironmentObject private var subtitleStore: SubtitleStore

    var body: some View {
        Menu {
            if subtitleStore.tracks.isEmpty && !subtitleStore.isSearching {
                Text("No subtitles found").foregroundStyle(.secondary)
            }
            if subtitleStore.isSearching {
                Text("Searching…").foregroundStyle(.secondary)
            }
            ForEach(subtitleStore.tracks) { track in
                Button(action: { subtitleStore.load(track: track) }) {
                    Label("\(track.languageName)  ★\(String(format: "%.1f", track.rating))",
                          systemImage: "captions.bubble")
                }
            }
            if subtitleStore.currentCue != nil || !subtitleStore.cues.isEmpty {
                Divider()
                Button("Clear subtitles", role: .destructive) { subtitleStore.clear() }
            }
        } label: {
            Image(systemName: subtitleStore.cues.isEmpty ? "captions.bubble" : "captions.bubble.fill")
                .font(.title3)
                .foregroundStyle(subtitleStore.cues.isEmpty ? Color.aetherText : Color.aetherAccent)
        }
        .menuStyle(.borderlessButton)
        .help("Subtitles")
    }
}

// MARK: - ErrorRetryView

/// Overlay shown when playback fails — displays the error message and a Retry button.
struct ErrorRetryView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)

            Text(message)
                .font(.aetherCaption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 220)

            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.aetherPrimary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - FavoriteButton

fileprivate struct FavoriteButton: View {
    let channel: Channel?
    @Query private var favorites: [FavoriteRecord]
    @Environment(\.modelContext) private var modelContext

    private var isFavorite: Bool {
        guard let channel else { return false }
        return favorites.contains { $0.channelID == channel.id }
    }

    var body: some View {
        Button(action: toggleFavorite) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(isFavorite ? Color.aetherAccent : Color.aetherText)
        }
        .buttonStyle(.plain)
        .disabled(channel == nil)
        .help(isFavorite ? "Remove from Favorites  F" : "Add to Favorites  F")
        .keyboardShortcut("f", modifiers: [])
    }

    private func toggleFavorite() {
        guard let channel else { return }
        if let existing = favorites.first(where: { $0.channelID == channel.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteRecord(channel: channel))
        }
    }
}

// MARK: - SleepTimerButton

fileprivate struct SleepTimerButton: View {
    @EnvironmentObject private var sleepTimer: SleepTimerService
    @State private var showSheet = false

    var body: some View {
        Button(action: { showSheet = true }) {
            HStack(spacing: 4) {
                Image(systemName: sleepTimer.isActive ? "moon.fill" : "moon")
                    .font(.title3)
                    .foregroundStyle(sleepTimer.isActive ? Color.aetherAccent : Color.aetherText)
                if sleepTimer.isActive {
                    Text(sleepTimer.remainingFormatted)
                        .font(.aetherCaption)
                        .foregroundStyle(Color.aetherAccent)
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
        .help(sleepTimer.isActive ? "Sleep timer active — click to change" : "Set sleep timer")
        .sheet(isPresented: $showSheet) {
            SleepTimerView()
        }
    }
}

// MARK: - SleepTimerView

fileprivate struct SleepTimerView: View {
    @EnvironmentObject private var sleepTimer: SleepTimerService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Sleep Timer")
                .font(.aetherHeadline)
                .foregroundStyle(Color.aetherText)

            if sleepTimer.isActive {
                VStack(spacing: 8) {
                    Text("Time remaining")
                        .font(.aetherCaption)
                        .foregroundStyle(Color.aetherText.opacity(0.6))
                    Text(sleepTimer.remainingFormatted)
                        .font(.system(size: 40, weight: .thin, design: .monospaced))
                        .foregroundStyle(Color.aetherAccent)
                        .monospacedDigit()
                }
                .padding(.vertical, 8)

                Button(role: .destructive) {
                    sleepTimer.cancel()
                    dismiss()
                } label: {
                    Label("Cancel Timer", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.aetherPrimary)
            } else {
                Text("Auto-stop playback after:")
                    .font(.aetherCaption)
                    .foregroundStyle(Color.aetherText.opacity(0.7))

                VStack(spacing: 10) {
                    ForEach(SleepTimerDuration.allCases, id: \.self) { duration in
                        Button(action: {
                            sleepTimer.start(duration: duration)
                            dismiss()
                        }) {
                            Text(duration.label)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.aetherPrimary)
                    }
                }
            }

            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.aetherText.opacity(0.5))
        }
        .padding(24)
        .frame(width: 260)
        .background(Color.aetherBackground)
    }
}
