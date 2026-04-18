     1|import SwiftUI
     2|import SwiftData
     3|import AetherCore
     4|
     5|/// Root view: Fullscreen player with floating channel panel overlay.
     6|struct ContentView: View {
     7|    @EnvironmentObject private var epgStore: EPGStore
     8|    @EnvironmentObject private var networkMonitor: NetworkMonitorService
     9|    @EnvironmentObject private var themeService: ThemeService
    10|    @Bindable var playerCore: PlayerCore
    11|
    12|    @State private var selectedPlaylist: PlaylistRecord?
    13|    @State private var selectedChannel: Channel?
    14|    @State private var showChannelPanel = false
    15|    #if os(macOS)
    16|    @State private var showCommandPalette = false
    17|    #endif
    18|    
    19|    @AppStorage("preferredColorScheme") private var preferredScheme: String = "auto"
    20|    
    21|    private var resolvedColorScheme: ColorScheme? {
    22|        switch preferredScheme {
    23|        case "light": return .light
    24|        case "dark": return .dark
    25|        default: return nil
    26|        }
    27|    }
    28|
    29|    // Keyboard handler — retained for the lifetime of this view (macOS only)
    30|    #if os(macOS)
    31|    private let keyboardHandler: KeyboardShortcutHandler
    32|    #endif
    33|
    34|    init(playerCore: PlayerCore) {
    35|        self.playerCore = playerCore
    36|        #if os(macOS)
    37|        self.keyboardHandler = KeyboardShortcutHandler(playerCore: playerCore)
    38|        #endif
    39|    }
    40|
    41|    var body: some View {
    42|        ZStack {
    43|            // Base layer: Fullscreen player
    44|            PlayerView(player: playerCore)
    45|                .ignoresSafeArea()
    46|
    47|            // Network status banner
    48|            VStack {
    49|                NetworkStatusBanner(networkMonitor: networkMonitor)
    50|                Spacer()
    51|            }
    52|            .ignoresSafeArea()
    53|
    54|            // Floating channel panel overlay
    55|            if showChannelPanel {
    56|                ZStack {
    57|                    // Dismissal backdrop
    58|                    Color.black.opacity(0.3)
    59|                        .ignoresSafeArea()
    60|                        .onTapGesture { showChannelPanel = false }
    61|
    62|                    FloatingChannelPanel(
    63|                        isVisible: $showChannelPanel,
    64|                        selectedPlaylist: $selectedPlaylist,
    65|                        selectedChannel: $selectedChannel,
    66|                        player: playerCore
    67|                    )
    68|                }
    69|                .transition(.asymmetric(
    70|                    insertion: .move(edge: .leading).combined(with: .opacity),
    71|                    removal: .move(edge: .leading).combined(with: .opacity)
    72|                ))
    73|            }
    74|
    75|            // Toggle button (top-left corner) - only show when panel is hidden
    76|            if !showChannelPanel {
    77|                VStack {
    78|                    HStack {
    79|                        Button(action: { showChannelPanel.toggle() }) {
    80|                            Image(systemName: "sidebar.left")
    81|                                .font(.system(size: 20))
    82|                                .foregroundStyle(.white)
    83|                                .padding(12)
    84|                                .background(Color.black.opacity(0.5))
    85|                                .clipShape(Circle())
    86|                        }
    87|                        .buttonStyle(.plain)
    88|                        .help("Toggle Channel List  ⌘L")
    89|                        .padding(16)
    90|
    91|                        Spacer()
    92|                    }
    93|                    Spacer()
    94|                }
    95|                .transition(.opacity)
    96|            }
    97|
    98|            // Command Palette overlay
    99|            #if os(macOS)
   100|            if showCommandPalette {
   101|                ZStack {
   102|                    // Dismissal backdrop
   103|                    Color.clear
   104|                        .contentShape(Rectangle())
   105|                        .ignoresSafeArea()
   106|                        .onTapGesture { showCommandPalette = false }
   107|
   108|                    CommandPaletteView(
   109|                        isPresented: $showCommandPalette,
   110|                        player: playerCore,
   111|                        channels: playerCore.channelList
   112|                    )
   113|                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
   114|                    .padding(.top, 60)
   115|                }
   116|                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
   117|            }
   118|            #endif
   119|        }
   120|        .animation(.spring(duration: 0.3), value: showChannelPanel)
   121|        .background(themeService.active.backgroundView())
   122|        .preferredColorScheme(resolvedColorScheme)
   123|        .onChange(of: selectedPlaylist) { _, newPlaylist in
   124|            guard let playlist = newPlaylist else {
   125|                playerCore.currentXstreamCredentials = nil
   126|                return
   127|            }
   128|            playerCore.currentXstreamCredentials = playlist.xstreamCredentials
   129|            Task { await epgStore.loadGuide(for: playlist) }
   130|        }
   131|        .onAppear {
   132|            #if os(macOS)
   133|            keyboardHandler.startMonitoring()
   134|            #endif
   135|            // Do not auto-restore last channel on launch — user picks manually
   136|        }
   137|        .onDisappear {
   138|            #if os(macOS)
   139|            keyboardHandler.stopMonitoring()
   140|            #endif
   141|        }
   142|        #if os(macOS)
   143|        .animation(.spring(duration: 0.2), value: showCommandPalette)
   144|        .onKeyPress(.init("k"), phases: .down) { event in
   145|            guard event.modifiers.contains(.command) else { return .ignored }
   146|            showCommandPalette.toggle()
   147|            return .handled
   148|        }
   149|        .onKeyPress(.init("l"), phases: .down) { event in
   150|            guard event.modifiers.contains(.command) else { return .ignored }
   151|            showChannelPanel.toggle()
   152|            return .handled
   153|        }
   154|        #endif
   155|    }
   156|}
   157|