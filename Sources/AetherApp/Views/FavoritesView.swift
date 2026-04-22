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
        case channels = "Channels"
        case vod      = "Filmy"
        case series   = "Seriale"
    }

    @State private var selectedTab: FavTab = .channels
    @State private var selectedChannel: Channel?

    private var channelFavorites: [FavoriteRecord] {
        favorites.filter { $0.contentType == "channel" || $0.contentType.isEmpty }
    }

    private var vodFavorites: [FavoriteRecord] {
        favorites.filter { $0.contentType == "vod" }
    }

    private var seriesFavorites: [FavoriteRecord] {
        favorites.filter { $0.contentType == "series" }
    }

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
                    vodContent
                case .series:
                    seriesContent
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
        let channels = channelFavorites.compactMap { $0.toChannel() }
        if channels.isEmpty {
            emptyState(
                icon: "star",
                title: "No favorite channels",
                subtitle: "Press the star next to a channel to add it to favorites"
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

    // MARK: VOD

    @ViewBuilder
    private var vodContent: some View {
        if vodFavorites.isEmpty {
            emptyState(
                icon: "film",
                title: "No favorite movies",
                subtitle: "Open a movie and press the star to add it to favorites"
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)], spacing: 16) {
                    ForEach(vodFavorites) { record in
                        posterCard(record: record)
                            .onTapGesture {
                                if let channel = record.toChannel() {
                                    player.play(channel)
                                }
                            }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Series

    @ViewBuilder
    private var seriesContent: some View {
        if seriesFavorites.isEmpty {
            emptyState(
                icon: "tv",
                title: "No favorite series",
                subtitle: "Open a series and press the star to add it to favorites"
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)], spacing: 16) {
                    ForEach(seriesFavorites) { record in
                        posterCard(record: record)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Poster card (VOD / Series)

    private func posterCard(record: FavoriteRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: record.logoURLString.flatMap(URL.init(string:))) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    Color(.sRGB, red: 0.15, green: 0.15, blue: 0.18, opacity: 1)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .frame(width: 120, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(record.channelName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)

            Button(role: .destructive) {
                removeFavoriteRecord(record)
            } label: {
                Image(systemName: "star.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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

    private func removeFavoriteRecord(_ record: FavoriteRecord) {
        modelContext.delete(record)
        try? modelContext.save()
    }
}
