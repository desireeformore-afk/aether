import SwiftUI
import SwiftData
import AVKit
import AetherCore

/// Detail pane: AVPlayer video + transport controls + EPG info bar.
struct PlayerView: View {
    @EnvironmentObject private var epgStore: EPGStore
    @ObservedObject var player: PlayerCore

    @State private var nowPlaying: EPGEntry?
    @State private var nextUp: EPGEntry?

    var body: some View {
        ZStack {
            Color.aetherBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Video layer
                VideoPlayerLayer(avPlayer: player.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding([.horizontal, .top])
                    .overlay(alignment: .bottomLeading) {
                        stateOverlay
                            .padding([.horizontal, .bottom], 20)
                    }

                // EPG info bar
                if let entry = nowPlaying {
                    EPGInfoBar(current: entry, next: nextUp)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                Spacer(minLength: 8)

                // Controls
                PlayerControls(player: player)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
        .onChange(of: player.currentChannel) { _, newChannel in
            Task { await loadEPG(for: newChannel) }
        }
        // Keyboard shortcuts (6c)
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
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch player.state {
        case .loading:
            ProgressView()
                .scaleEffect(1.5)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .error(let msg):
            ErrorRetryView(message: msg) {
                if let channel = player.currentChannel {
                    player.play(channel)
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
            return
        }
        let cid = channel.epgId ?? channel.name
        let now = Date()
        nowPlaying = await epgStore.service.nowPlaying(for: cid, at: now)
        nextUp    = await epgStore.service.nextUp(for: cid, at: now)
    }
}

// MARK: - EPGInfoBar

struct EPGInfoBar: View {
    let current: EPGEntry
    let next: EPGEntry?

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

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = avPlayer
        // Show native controls including fullscreen and PiP buttons
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== avPlayer { nsView.player = avPlayer }
    }
}

// MARK: - PlayerControls

struct PlayerControls: View {
    @ObservedObject var player: PlayerCore
    @Environment(\.modelContext) private var modelContext

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

            // Favorite toggle
            FavoriteButton(channel: player.currentChannel)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var isPlaying: Bool { player.state == .playing }
    private var playPauseIcon: String { isPlaying ? "pause.fill" : "play.fill" }
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
