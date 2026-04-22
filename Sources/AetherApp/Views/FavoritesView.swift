import SwiftUI
import SwiftData
import AetherCore
import AetherUI

// MARK: - FavoritesView

struct FavoritesView: View {
    @Bindable var player: PlayerCore

    @Query(sort: \FavoriteRecord.addedAt, order: .reverse)
    private var favorites: [FavoriteRecord]

    @Environment(\.modelContext) private var modelContext

    enum FavTab: String, CaseIterable {
        case channels = "Kanały"
        case vod      = "Filmy"
        case series   = "Seriale"
    }

    @State private var selectedTab: FavTab = .channels
    @State private var selectedChannel: Channel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Segmented picker header
                Picker("", selection: $selectedTab) {
                    ForEach(FavTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().opacity(0.15)

                switch selectedTab {
                case .channels:
                    channelsContent
                case .vod:
                    emptyState(
                        icon: "film",
                        title: "Brak ulubionych filmów",
                        subtitle: "Otwórz film i naciśnij gwiazdkę, aby dodać do ulubionych"
                    )
                case .series:
                    emptyState(
                        icon: "tv",
                        title: "Brak ulubionych seriali",
                        subtitle: "Otwórz serial i naciśnij gwiazdkę, aby dodać do ulubionych"
                    )
                }
            }
        }
        .navigationTitle("Ulubione")
        .onChange(of: selectedChannel) { _, channel in
            guard let channel else { return }
            player.play(channel)
        }
    }

    // MARK: Channels

    @ViewBuilder
    private var channelsContent: some View {
        let channels = favorites.compactMap { $0.toChannel() }
        if channels.isEmpty {
            emptyState(
                icon: "star",
                title: "Brak ulubionych kanałów",
                subtitle: "Naciśnij gwiazdkę przy kanale, aby dodać go do ulubionych"
            )
        } else {
            List(selection: $selectedChannel) {
                ForEach(channels) { channel in
                    favoriteChannelRow(channel)
                        .tag(channel)
                }
                .onDelete { offsets in
                    removeFavorites(at: offsets, from: channels)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func favoriteChannelRow(_ channel: Channel) -> some View {
        HStack(spacing: 12) {
            ChannelLogoView(
                url: channel.logoURL,
                size: 36,
                channelName: channel.name
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(channel.groupTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(channel.name), \(channel.groupTitle)")
    }

    // MARK: Empty state

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func removeFavorites(at offsets: IndexSet, from channels: [Channel]) {
        let idsToRemove = offsets.map { channels[$0].id }
        for id in idsToRemove {
            let matching = (try? modelContext.fetch(
                FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.channelID == id })
            )) ?? []
            matching.forEach { modelContext.delete($0) }
        }
        try? modelContext.save()
    }
}
