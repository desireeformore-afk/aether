import SwiftUI
import SwiftData
import AetherCore

/// Root view: Fullscreen player with floating channel panel overlay.
struct ContentView: View {
    @EnvironmentObject private var epgStore: EPGStore
    @ObservedObject var playerCore: PlayerCore

    @State private var selectedPlaylist: PlaylistRecord?
    @State private var selectedChannel: Channel?
    @State private var showChannelPanel = false
    #if os(macOS)
    @State private var showCommandPalette = false
    #endif

    // Keyboard handler — retained for the lifetime of this view (macOS only)
    #if os(macOS)
    private let keyboardHandler: KeyboardShortcutHandler
    #endif

    init(playerCore: PlayerCore) {
        self.playerCore = playerCore
        #if os(macOS)
        self.keyboardHandler = KeyboardShortcutHandler(playerCore: playerCore)
        #endif
    }

    var body: some View {
        ZStack {
            // Base layer: Fullscreen player
            PlayerView(player: playerCore)
                .ignoresSafeArea()

            // Floating channel panel overlay
            if showChannelPanel {
                ZStack {
                    // Dismissal backdrop
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showChannelPanel = false }

                    FloatingChannelPanel(
                        isVisible: $showChannelPanel,
                        selectedPlaylist: $selectedPlaylist,
                        selectedChannel: $selectedChannel,
                        player: playerCore
                    )
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }

            // Toggle button (top-left corner) - only show when panel is hidden
            if !showChannelPanel {
                VStack {
                    HStack {
                        Button(action: { showChannelPanel.toggle() }) {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Channel List  ⌘L")
                        .padding(16)

                        Spacer()
                    }
                    Spacer()
                }
                .transition(.opacity)
            }

            // Command Palette overlay
            #if os(macOS)
            if showCommandPalette {
                ZStack {
                    // Dismissal backdrop
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }

                    CommandPaletteView(
                        isPresented: $showCommandPalette,
                        player: playerCore,
                        channels: playerCore.channelList
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            #endif
        }
        .animation(.spring(duration: 0.3), value: showChannelPanel)
        .background(Color.aetherBackground)
        .onChange(of: selectedPlaylist) { _, newPlaylist in
            guard let playlist = newPlaylist else {
                playerCore.currentXstreamCredentials = nil
                return
            }
            playerCore.currentXstreamCredentials = playlist.xstreamCredentials
            Task { await epgStore.loadGuide(for: playlist) }
        }
        .onAppear {
            #if os(macOS)
            keyboardHandler.startMonitoring()
            #endif
            // Do not auto-restore last channel on launch — user picks manually
        }
        .onDisappear {
            #if os(macOS)
            keyboardHandler.stopMonitoring()
            #endif
        }
        #if os(macOS)
        .animation(.spring(duration: 0.2), value: showCommandPalette)
        .onKeyPress(.init("k"), phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            showCommandPalette.toggle()
            return .handled
        }
        .onKeyPress(.init("l"), phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            showChannelPanel.toggle()
            return .handled
        }
        #endif
    }
}
