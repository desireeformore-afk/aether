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
            // Header
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
                Picker("Season", selection: $selectedSeason) {
                    ForEach(seasons, id: \.self) { s in
                        Text("Season \(s)").tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                let episodes = (info.episodes[selectedSeason] ?? [])
                    .sorted { $0.episodeNum < $1.episodeNum }

                List(episodes) { ep in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("E\(ep.episodeNum)  \(ep.title)")
                                .font(.aetherBody)
                                .foregroundStyle(Color.aetherText)
                            if let plot = ep.info?.plot {
                                Text(plot)
                                    .font(.aetherCaption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Button("▶ Play") {
                            playEpisode(ep)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.aetherPrimary)
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    if let first = seasons.first { selectedSeason = first }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color.aetherBackground)
        .task { await loadInfo() }
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

        // Deterministic UUID from episode ID (series namespace offset: 0xC00000000000)
        // so watch history can track the same episode across sessions.
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
