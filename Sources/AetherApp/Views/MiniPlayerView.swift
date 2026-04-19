import SwiftUI
import AetherCore

/// Mini player window - compact always-on-top player.
public struct MiniPlayerView: View {
    @Bindable var player: PlayerCore
    @Environment(EPGStore.self) private var epgStore
    @Binding var isPresented: Bool

    @State private var nowPlaying: EPGEntry?
    @State private var isHovering = false

    public init(player: PlayerCore, isPresented: Binding<Bool>) {
        self.player = player
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            // Video layer
            VideoPlayerLayer(avPlayer: player.player, playerCore: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Overlay controls (show on hover)
            if isHovering || player.state != .playing {
                VStack {
                    // Top bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentChannel?.name ?? "No channel")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if let entry = nowPlaying {
                                Text(entry.title)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        // Close button
                        Button(action: {
                            isPresented = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial.opacity(0.8))

                    Spacer()

                    // Bottom controls
                    HStack(spacing: 12) {
                        Button(action: { player.playPrevious() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: { player.togglePlayPause() }) {
                            Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: { player.playNext() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .frame(height: 16)
                            .background(.white.opacity(0.5))

                        Button(action: { player.toggleMute() }) {
                            Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial.opacity(0.8))
                }
                .transition(.opacity)
            }
        }
        .frame(width: 300, height: 169) // 16:9 aspect ratio
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        #if os(macOS)
        .onScrollWheel { event in
            let delta = Float(event.scrollingDeltaY) * 0.005
            player.adjustVolume(delta: -delta)
        }
        #endif
        .onChange(of: player.currentChannel) { _, newChannel in
            Task {
                await loadEPG(for: newChannel)
            }
        }
        .task {
            await loadEPG(for: player.currentChannel)
        }
    }

    private func loadEPG(for channel: Channel?) async {
        guard let channel else {
            nowPlaying = nil
            return
        }
        let cid = channel.epgId ?? channel.name
        nowPlaying = await epgStore.service.nowPlaying(for: cid, at: Date())
    }
}

/// Mini player window controller.
@MainActor
@Observable
public final class MiniPlayerWindowController {
    public var isShowing = false

    private var window: NSWindow?
    private let player: PlayerCore

    public init(player: PlayerCore) {
        self.player = player
    }

    public func show() {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = MiniPlayerView(player: player, isPresented: Binding(
            get: { self.isShowing },
            set: { self.isShowing = $0 }
        ))
        .environment(EPGStore())

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Aether Mini Player"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.level = .floating // Always on top
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Set initial size
        window.setContentSize(NSSize(width: 300, height: 169))
        window.minSize = NSSize(width: 200, height: 113)
        window.maxSize = NSSize(width: 600, height: 338)

        // Center on screen
        window.center()

        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.isShowing = true

        // Handle window close
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isShowing = false
                self?.window = nil
            }
        }
    }

    public func hide() {
        window?.close()
        window = nil
        isShowing = false
    }

    public func toggle() {
        if isShowing {
            hide()
        } else {
            show()
        }
    }
}
