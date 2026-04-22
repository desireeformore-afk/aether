import SwiftUI
import AetherCore

struct SeriesDetailView: View {
    let series: XstreamSeries
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    @Environment(\.dismiss) private var dismiss

    @State private var info: XstreamSeriesInfo?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedSeason: String = "1"

    private let service: XstreamService

    init(series: XstreamSeries, credentials: XstreamCredentials, player: PlayerCore) {
        self.series = series
        self.credentials = credentials
        self.player = player
        self.service = XstreamService(credentials: credentials)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading episodes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let error = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Failed to load episodes")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") { Task { await loadInfo() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let info {
                let seasons = info.episodes.keys.sorted { Int($0) ?? 0 < Int($1) ?? 0 }
                let episodes = (info.episodes[selectedSeason] ?? [])
                    .sorted { $0.episodeNum < $1.episodeNum }

                VStack(spacing: 0) {
                    if seasons.count > 1 {
                        Picker("Season", selection: $selectedSeason) {
                            ForEach(seasons, id: \.self) { s in
                                Text("Sezon \(s)").tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 6) {
                            ForEach(episodes) { ep in
                                episodeCard(ep)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .onAppear {
                    if let first = seasons.first { selectedSeason = first }
                }
            }
        }
        .frame(minWidth: 580, minHeight: 460)
        .background(Color.aetherBackground)
        .task { await loadInfo() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    Color.aetherSurface
                }
            }
            .frame(width: 90, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(series.name)
                    .font(.aetherTitle)
                    .foregroundStyle(Color.aetherText)
                if let genre = series.genre {
                    Text(genre)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                }
                if let plot = series.plot {
                    Text(plot)
                        .font(.aetherCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    // MARK: - Episode card

    private func episodeCard(_ ep: XstreamEpisode) -> some View {
        Button {
            playEpisode(ep)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                // Thumbnail — series cover as visual placeholder
                ZStack {
                    AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Color(.sRGB, red: 0.15, green: 0.15, blue: 0.18, opacity: 1)
                        }
                    }
                    .frame(width: 100, height: 62)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(.black.opacity(0.30))
                        .frame(width: 100, height: 62)

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
                .frame(width: 100, height: 62)

                // Episode info
                VStack(alignment: .leading, spacing: 4) {
                    Text("E\(ep.episodeNum)  \(ep.title)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.aetherText)
                        .lineLimit(1)

                    if let plot = ep.info?.plot, !plot.isEmpty {
                        Text(plot)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let dur = ep.info?.durationSecs, dur > 0 {
                        Text(formatDuration(dur))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color(.sRGB, red: 0.12, green: 0.12, blue: 0.16, opacity: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatDuration(_ secs: Int) -> String {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)min" }
        return "\(m) min"
    }

    private func loadInfo() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            info = try await service.seriesInfo(seriesID: series.id)
        } catch {
            if info == nil {
                loadError = error.localizedDescription
            }
        }
    }

    private func playEpisode(_ ep: XstreamEpisode) {
        let ext = ep.containerExtension ?? "mp4"
        let url = credentials.streamURL(type: "series", id: ep.id, ext: ext)

        let epUID = ep.id + 0xC00000000000
        let deterministicID = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", epUID))") ?? UUID()

        let channel = Channel(
            id: deterministicID,
            name: "\(series.name) — S\(ep.season)E\(ep.episodeNum) \(ep.title)",
            streamURL: url,
            logoURL: series.cover.flatMap(URL.init(string:)),
            groupTitle: "Series",
            epgId: nil,
            contentType: .series
        )
        Task { @MainActor in
            player.play(channel)
        }
    }
}
