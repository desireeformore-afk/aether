import SwiftUI
import SwiftData
import AetherCore

/// Floating sidebar panel that slides in from the left, containing playlist selector and channel list.
struct FloatingChannelPanel: View {
    @Binding var isVisible: Bool
    @Binding var selectedPlaylist: PlaylistRecord?
    @Binding var selectedChannel: Channel?
    @ObservedObject var player: PlayerCore

    @State private var showVODBrowser = false
    @State private var showSeriesBrowser = false
    @State private var showGlobalSearch = false
    #if os(macOS)
    @State private var showSettings = false
    #endif

    var body: some View {
        HStack(spacing: 0) {
            // Panel content - side-by-side layout
            HStack(spacing: 0) {
                // Playlist selector on left
                PlaylistSidebar(selectedPlaylist: $selectedPlaylist)
                    .frame(width: 280)

                Divider()

                // Channel list on right
                if let playlist = selectedPlaylist {
                    VStack(spacing: 0) {
                        // Search All button at top for Xtream playlists
                        if playlist.playlistType == .xtream,
                           let creds = playlist.xstreamCredentials {
                            Button(action: { showGlobalSearch = true }) {
                                Label("Search All Content", systemImage: "magnifyingglass.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .sheet(isPresented: $showGlobalSearch) {
                                GlobalContentSearchView(
                                    xstreamService: XstreamService(credentials: creds)
                                )
                            }

                            Divider()
                        }

                        ChannelListView(
                            playlist: playlist,
                            selectedChannel: $selectedChannel,
                            player: player
                        )

                        // VOD/Series/Search buttons at bottom if Xtream Codes
                        if playlist.playlistType == .xtream,
                           let creds = playlist.xstreamCredentials {
                            Divider()
                            HStack(spacing: 12) {
                                Button(action: { showGlobalSearch = true }) {
                                    Label("Search", systemImage: "magnifyingglass.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .sheet(isPresented: $showGlobalSearch) {
                                    GlobalContentSearchView(
                                        xstreamService: XstreamService(credentials: creds)
                                    )
                                }
                                
                                Button(action: { showVODBrowser = true }) {
                                    Label("VOD", systemImage: "film.stack")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .sheet(isPresented: $showVODBrowser) {
                                    VODBrowserView(credentials: creds, player: player)
                                }

                                Button(action: { showSeriesBrowser = true }) {
                                    Label("Series", systemImage: "tv.and.mediabox")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .sheet(isPresented: $showSeriesBrowser) {
                                    SeriesBrowserView(credentials: creds, player: player)
                                }

                                Button(action: { showGlobalSearch = true }) {
                                    Label("Search All", systemImage: "magnifyingglass")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .sheet(isPresented: $showGlobalSearch) {
                                    GlobalContentSearchView(
                                        xstreamService: XstreamService(credentials: creds)
                                    )
                                }
                            }
                            .padding(12)
                        }
                    }
                    .frame(width: 360)
                } else {
                    ContentUnavailableView(
                        "No Playlist Selected",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Add a playlist to get started.")
                    )
                    .frame(width: 360)
                    .background(Color.aetherBackground)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.aetherBackground.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 5, y: 0)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.vertical, 16)
    }
}
