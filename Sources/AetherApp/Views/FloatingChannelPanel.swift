import SwiftUI
import SwiftData
import AetherCore

/// Floating sidebar panel that slides in from the left.
/// Contains playlist selector, and content tabs: Live TV / Movies (VOD) / Series.
struct FloatingChannelPanel: View {
    @Binding var isVisible: Bool
    @Binding var selectedPlaylist: PlaylistRecord?
    @Binding var selectedChannel: Channel?
    @Bindable var player: PlayerCore
    /// Incremented by ContentView keyboard handler to activate search in the channel list.
    var searchActivationToken: Int = 0

    @State private var activeTab: PanelTab = .tv
    @State private var showGlobalSearch = false

    #if os(macOS)
    @State private var showSettings = false
    #endif

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left: Playlist selector
                PlaylistSidebar(selectedPlaylist: $selectedPlaylist)
                    .frame(width: 180)

                Divider()

                // Right: Content area
                VStack(spacing: 0) {
                    if let playlist = selectedPlaylist {
                        // Tab bar
                        tabBar(for: playlist)

                        Divider()

                        // Tab content
                        tabContent(for: playlist)
                    } else {
                        ContentUnavailableView(
                            "No Playlist Selected",
                            systemImage: "list.bullet.rectangle",
                            description: Text("Add a playlist to get started.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.aetherBackground)
                    }
                }
                .frame(width: 420)
            }
            .frame(maxHeight: .infinity)
            .background(Color.aetherBackground.opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.35), radius: 20, x: 5, y: 0)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.vertical, 16)
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private func tabBar(for playlist: PlaylistRecord) -> some View {
        HStack(spacing: 0) {
            ForEach(availableTabs(for: playlist), id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        activeTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: activeTab == tab ? .semibold : .regular))
                        Text(tab.label)
                            .font(.system(size: 10, weight: activeTab == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(activeTab == tab ? Color.aetherPrimary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        activeTab == tab
                            ? Color.aetherPrimary.opacity(0.15)
                            : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            // Search icon at the right end (Xtream only)
            if playlist.playlistType == .xtream, let creds = playlist.xstreamCredentials {
                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)

                Button {
                    showGlobalSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .help("Search All Content  ⌘F")
                .sheet(isPresented: $showGlobalSearch) {
                    GlobalContentSearchView(
                        xstreamService: XstreamService(credentials: creds),
                        credentials: creds,
                        player: player
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.aetherSurface)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(for playlist: PlaylistRecord) -> some View {
        switch activeTab {
        case .tv:
            ChannelListView(
                playlist: playlist,
                selectedChannel: $selectedChannel,
                player: player,
                searchActivationToken: searchActivationToken
            )
            .contentTransition(.opacity)

        case .movies:
            if let creds = playlist.xstreamCredentials {
                VODBrowserView(credentials: creds, player: player, isEmbedded: true)
                    .contentTransition(.opacity)
            } else {
                unavailableView("Movies unavailable", systemImage: "film", description: "Movies require an Xtream Codes playlist.")
            }

        case .series:
            if let creds = playlist.xstreamCredentials {
                SeriesBrowserView(credentials: creds, player: player, isEmbedded: true)
                    .contentTransition(.opacity)
            } else {
                unavailableView("Series unavailable", systemImage: "tv.and.mediabox", description: "Series require an Xtream Codes playlist.")
            }
        }
    }

    // MARK: - Helpers

    private func availableTabs(for playlist: PlaylistRecord) -> [PanelTab] {
        if playlist.playlistType == .xtream {
            return PanelTab.allCases
        }
        return [.tv]
    }

    private func unavailableView(_ title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PanelTab

enum PanelTab: String, CaseIterable {
    case tv = "TV"
    case movies = "Movies"
    case series = "Series"

    var label: String { rawValue }

    var icon: String {
        switch self {
        case .tv:      return "tv"
        case .movies:  return "film.stack"
        case .series:  return "tv.and.mediabox"
        }
    }
}
