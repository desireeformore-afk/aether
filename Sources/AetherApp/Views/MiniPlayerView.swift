import SwiftUI
import AetherCore

/// Mini player window - compact always-on-top player.
public struct MiniPlayerView: View {
    @Bindable var player: PlayerCore
    @Environment(EPGStore.self) private var epgStore
    @Binding var isPresented: Bool
    var onExpand: (() -> Void)?

    @State private var nowPlaying: EPGEntry?
    @State private var isHovering = false

    public init(player: PlayerCore, isPresented: Binding<Bool>, onExpand: (() -> Void)? = nil) {
        self.player = player
        self._isPresented = isPresented
        self.onExpand = onExpand
    }

    public var body: some View {
        ZStack {
            // Video layer — VLC renders directly into NSView
            VLCVideoView(player: player)
                .aspectRatio(16 / 9, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Overlay controls (show on hover or when not playing)
            VStack(spacing: 0) {
                // Top bar: logo + channel/EPG info + expand + close
                HStack(spacing: 8) {
                    if let logoURL = player.currentChannel?.logoURL {
                        AsyncImage(url: logoURL) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFit()
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white.opacity(0.15))
                            }
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.currentChannel?.name ?? "No channel")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let entry = nowPlaying {
                            Text(entry.title)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Expand back to main window
                    Button {
                        onExpand?()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Expand to main window")

                    // Close button
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)

                Spacer()

                // Bottom controls
                HStack(spacing: 14) {
                    Button { player.playPrevious() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button { player.playNext() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 14)
                        .overlay(.white.opacity(0.4))

                    Button { player.toggleMute() } label: {
                        Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            .opacity(isHovering || player.state != .playing ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .animation(.easeInOut(duration: 0.2), value: player.state == .playing)
        }
        .frame(minWidth: 280, minHeight: 80)
        .onHover { hovering in
            isHovering = hovering
        }
        #if os(macOS)
        .onScrollWheel { event in
            let delta = Float(event.scrollingDeltaY) * 0.005
            player.adjustVolume(delta: -delta)
        }
        #endif
        .onChange(of: player.currentChannel) { _, newChannel in
            Task { await loadEPG(for: newChannel) }
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
    public var epgStore: EPGStore = EPGStore()

    public init(player: PlayerCore) {
        self.player = player
    }

    public func show() {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = MiniPlayerView(
            player: player,
            isPresented: Binding(get: { self.isShowing }, set: { self.isShowing = $0 }),
            onExpand: { [weak self] in
                self?.hide()
                NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            }
        )
        .environment(epgStore)

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
        window.setContentSize(NSSize(width: 320, height: 180))
        window.minSize = NSSize(width: 280, height: 80)
        window.maxSize = NSSize(width: 640, height: 360)

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
