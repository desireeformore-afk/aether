     1|import SwiftUI
     2|import SwiftData
     3|import AetherCore
     4|
     5|/// Floating sidebar panel that slides in from the left, containing playlist selector and channel list.
     6|struct FloatingChannelPanel: View {
     7|    @Binding var isVisible: Bool
     8|    @Binding var selectedPlaylist: PlaylistRecord?
     9|    @Binding var selectedChannel: Channel?
    10|    @Bindable var player: PlayerCore
    11|
    12|    @State private var showVODBrowser = false
    13|    @State private var showSeriesBrowser = false
    14|    @State private var showGlobalSearch = false
    15|    #if os(macOS)
    16|    @State private var showSettings = false
    17|    #endif
    18|
    19|    var body: some View {
    20|        HStack(spacing: 0) {
    21|            // Panel content - side-by-side layout
    22|            HStack(spacing: 0) {
    23|                // Playlist selector on left
    24|                PlaylistSidebar(selectedPlaylist: $selectedPlaylist)
    25|                    .frame(width: 280)
    26|
    27|                Divider()
    28|
    29|                // Channel list on right
    30|                if let playlist = selectedPlaylist {
    31|                    VStack(spacing: 0) {
    32|                        // Search All button at top for Xtream playlists
    33|                        if playlist.playlistType == .xtream,
    34|                           let creds = playlist.xstreamCredentials {
    35|                            Button(action: { showGlobalSearch = true }) {
    36|                                Label("Search All Content", systemImage: "magnifyingglass.circle")
    37|                                    .frame(maxWidth: .infinity)
    38|                            }
    39|                            .buttonStyle(.bordered)
    40|                            .padding(.horizontal, 12)
    41|                            .padding(.vertical, 8)
    42|                            .sheet(isPresented: $showGlobalSearch) {
    43|                                GlobalContentSearchView(
    44|                                    xstreamService: XstreamService(credentials: creds)
    45|                                )
    46|                            }
    47|
    48|                            Divider()
    49|                        }
    50|
    51|                        ChannelListView(
    52|                            playlist: playlist,
    53|                            selectedChannel: $selectedChannel,
    54|                            player: player
    55|                        )
    56|
    57|                        // VOD/Series/Search buttons at bottom if Xtream Codes
    58|                        if playlist.playlistType == .xtream,
    59|                           let creds = playlist.xstreamCredentials {
    60|                            Divider()
    61|                            HStack(spacing: 12) {
    62|                                Button(action: { showGlobalSearch = true }) {
    63|                                    Label("Search", systemImage: "magnifyingglass.circle")
    64|                                        .frame(maxWidth: .infinity)
    65|                                }
    66|                                .buttonStyle(.bordered)
    67|                                .sheet(isPresented: $showGlobalSearch) {
    68|                                    GlobalContentSearchView(
    69|                                        xstreamService: XstreamService(credentials: creds)
    70|                                    )
    71|                                }
    72|                                
    73|                                Button(action: { showVODBrowser = true }) {
    74|                                    Label("VOD", systemImage: "film.stack")
    75|                                        .frame(maxWidth: .infinity)
    76|                                }
    77|                                .buttonStyle(.bordered)
    78|                                .sheet(isPresented: $showVODBrowser) {
    79|                                    VODBrowserView(credentials: creds, player: player)
    80|                                }
    81|
    82|                                Button(action: { showSeriesBrowser = true }) {
    83|                                    Label("Series", systemImage: "tv.and.mediabox")
    84|                                        .frame(maxWidth: .infinity)
    85|                                }
    86|                                .buttonStyle(.bordered)
    87|                                .sheet(isPresented: $showSeriesBrowser) {
    88|                                    SeriesBrowserView(credentials: creds, player: player)
    89|                                }
    90|
    91|                                Button(action: { showGlobalSearch = true }) {
    92|                                    Label("Search All", systemImage: "magnifyingglass")
    93|                                        .frame(maxWidth: .infinity)
    94|                                }
    95|                                .buttonStyle(.bordered)
    96|                                .sheet(isPresented: $showGlobalSearch) {
    97|                                    GlobalContentSearchView(
    98|                                        xstreamService: XstreamService(credentials: creds)
    99|                                    )
   100|                                }
   101|                            }
   102|                            .padding(12)
   103|                        }
   104|                    }
   105|                    .frame(width: 360)
   106|                } else {
   107|                    ContentUnavailableView(
   108|                        "No Playlist Selected",
   109|                        systemImage: "list.bullet.rectangle",
   110|                        description: Text("Add a playlist to get started.")
   111|                    )
   112|                    .frame(width: 360)
   113|                    .background(Color.aetherBackground)
   114|                }
   115|            }
   116|            .frame(maxHeight: .infinity)
   117|            .background(Color.aetherBackground.opacity(0.95))
   118|            .clipShape(RoundedRectangle(cornerRadius: 12))
   119|            .shadow(color: .black.opacity(0.3), radius: 20, x: 5, y: 0)
   120|
   121|            Spacer()
   122|        }
   123|        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
   124|        .padding(.leading, 16)
   125|        .padding(.vertical, 16)
   126|    }
   127|}
   128|