     1|import SwiftUI
     2|import AetherCore
     3|
     4|/// Mini player window - compact always-on-top player.
     5|public struct MiniPlayerView: View {
     6|    @Bindable var player: PlayerCore
     7|    @EnvironmentObject private var epgStore: EPGStore
     8|    @Binding var isPresented: Bool
     9|
    10|    @State private var nowPlaying: EPGEntry?
    11|    @State private var isHovering = false
    12|
    13|    public init(player: PlayerCore, isPresented: Binding<Bool>) {
    14|        self.player = player
    15|        self._isPresented = isPresented
    16|    }
    17|
    18|    public var body: some View {
    19|        ZStack {
    20|            // Video layer
    21|            VideoPlayerLayer(avPlayer: player.player, playerCore: player)
    22|                .aspectRatio(16 / 9, contentMode: .fit)
    23|                .clipShape(RoundedRectangle(cornerRadius: 8))
    24|
    25|            // Overlay controls (show on hover)
    26|            if isHovering || player.state != .playing {
    27|                VStack {
    28|                    // Top bar
    29|                    HStack {
    30|                        VStack(alignment: .leading, spacing: 2) {
    31|                            Text(player.currentChannel?.name ?? "No channel")
    32|                                .font(.system(size: 11, weight: .semibold))
    33|                                .foregroundStyle(.white)
    34|                                .lineLimit(1)
    35|
    36|                            if let entry = nowPlaying {
    37|                                Text(entry.title)
    38|                                    .font(.system(size: 9))
    39|                                    .foregroundStyle(.white.opacity(0.8))
    40|                                    .lineLimit(1)
    41|                            }
    42|                        }
    43|
    44|                        Spacer()
    45|
    46|                        // Close button
    47|                        Button(action: {
    48|                            isPresented = false
    49|                        }) {
    50|                            Image(systemName: "xmark.circle.fill")
    51|                                .font(.system(size: 16))
    52|                                .foregroundStyle(.white.opacity(0.8))
    53|                        }
    54|                        .buttonStyle(.plain)
    55|                    }
    56|                    .padding(8)
    57|                    .background(.ultraThinMaterial.opacity(0.8))
    58|
    59|                    Spacer()
    60|
    61|                    // Bottom controls
    62|                    HStack(spacing: 12) {
    63|                        Button(action: { player.playPrevious() }) {
    64|                            Image(systemName: "backward.fill")
    65|                                .font(.system(size: 14))
    66|                                .foregroundStyle(.white)
    67|                        }
    68|                        .buttonStyle(.plain)
    69|
    70|                        Button(action: { player.togglePlayPause() }) {
    71|                            Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
    72|                                .font(.system(size: 16))
    73|                                .foregroundStyle(.white)
    74|                        }
    75|                        .buttonStyle(.plain)
    76|
    77|                        Button(action: { player.playNext() }) {
    78|                            Image(systemName: "forward.fill")
    79|                                .font(.system(size: 14))
    80|                                .foregroundStyle(.white)
    81|                        }
    82|                        .buttonStyle(.plain)
    83|
    84|                        Divider()
    85|                            .frame(height: 16)
    86|                            .background(.white.opacity(0.5))
    87|
    88|                        Button(action: { player.toggleMute() }) {
    89|                            Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
    90|                                .font(.system(size: 14))
    91|                                .foregroundStyle(.white)
    92|                        }
    93|                        .buttonStyle(.plain)
    94|                    }
    95|                    .padding(8)
    96|                    .background(.ultraThinMaterial.opacity(0.8))
    97|                }
    98|                .transition(.opacity)
    99|            }
   100|        }
   101|        .frame(width: 300, height: 169) // 16:9 aspect ratio
   102|        .onHover { hovering in
   103|            withAnimation(.easeInOut(duration: 0.2)) {
   104|                isHovering = hovering
   105|            }
   106|        }
   107|        .onChange(of: player.currentChannel) { _, newChannel in
   108|            Task {
   109|                await loadEPG(for: newChannel)
   110|            }
   111|        }
   112|        .task {
   113|            await loadEPG(for: player.currentChannel)
   114|        }
   115|    }
   116|
   117|    private func loadEPG(for channel: Channel?) async {
   118|        guard let channel else {
   119|            nowPlaying = nil
   120|            return
   121|        }
   122|        let cid = channel.epgId ?? channel.name
   123|        nowPlaying = await epgStore.service.nowPlaying(for: cid, at: Date())
   124|    }
   125|}
   126|
   127|/// Mini player window controller.
   128|@MainActor
   129|public final class MiniPlayerWindowController: ObservableObject {
   130|    @Published public var isShowing = false
   131|
   132|    private var window: NSWindow?
   133|    private let player: PlayerCore
   134|
   135|    public init(player: PlayerCore) {
   136|        self.player = player
   137|    }
   138|
   139|    public func show() {
   140|        guard window == nil else {
   141|            window?.makeKeyAndOrderFront(nil)
   142|            return
   143|        }
   144|
   145|        let contentView = MiniPlayerView(player: player, isPresented: Binding(
   146|            get: { self.isShowing },
   147|            set: { self.isShowing = $0 }
   148|        ))
   149|        .environmentObject(EPGStore())
   150|
   151|        let hostingController = NSHostingController(rootView: contentView)
   152|
   153|        let window = NSWindow(contentViewController: hostingController)
   154|        window.title = "Aether Mini Player"
   155|        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
   156|        window.level = .floating // Always on top
   157|        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
   158|        window.isMovableByWindowBackground = true
   159|        window.titlebarAppearsTransparent = true
   160|        window.titleVisibility = .hidden
   161|
   162|        // Set initial size
   163|        window.setContentSize(NSSize(width: 300, height: 169))
   164|        window.minSize = NSSize(width: 200, height: 113)
   165|        window.maxSize = NSSize(width: 600, height: 338)
   166|
   167|        // Center on screen
   168|        window.center()
   169|
   170|        window.makeKeyAndOrderFront(nil)
   171|
   172|        self.window = window
   173|        self.isShowing = true
   174|
   175|        // Handle window close
   176|        NotificationCenter.default.addObserver(
   177|            forName: NSWindow.willCloseNotification,
   178|            object: window,
   179|            queue: .main
   180|        ) { [weak self] _ in
   181|            Task { @MainActor in
   182|                self?.isShowing = false
   183|                self?.window = nil
   184|            }
   185|        }
   186|    }
   187|
   188|    public func hide() {
   189|        window?.close()
   190|        window = nil
   191|        isShowing = false
   192|    }
   193|
   194|    public func toggle() {
   195|        if isShowing {
   196|            hide()
   197|        } else {
   198|            show()
   199|        }
   200|    }
   201|}
   202|