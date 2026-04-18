     1|import SwiftUI
     2|import AetherCore
     3|
     4|struct SeriesDetailView: View {
     5|    let series: XstreamSeries
     6|    let credentials: XstreamCredentials
     7|    @Bindable var player: PlayerCore
     8|    @Environment(\.dismiss) private var dismiss
     9|
    10|    @State private var info: XstreamSeriesInfo?
    11|    @State private var isLoading = true
    12|    @State private var selectedSeason: String = "1"
    13|
    14|    private let service: XstreamService
    15|
    16|    init(series: XstreamSeries, credentials: XstreamCredentials, player: PlayerCore) {
    17|        self.series = series
    18|        self.credentials = credentials
    19|        self.player = player
    20|        self.service = XstreamService(credentials: credentials)
    21|    }
    22|
    23|    var body: some View {
    24|        VStack(spacing: 0) {
    25|            // Header
    26|            HStack(alignment: .top, spacing: 16) {
    27|                AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
    28|                    if case .success(let img) = phase {
    29|                        img.resizable().scaledToFill()
    30|                    } else {
    31|                        Color.aetherSurface
    32|                    }
    33|                }
    34|                .frame(width: 90, height: 130)
    35|                .clipShape(RoundedRectangle(cornerRadius: 8))
    36|
    37|                VStack(alignment: .leading, spacing: 6) {
    38|                    Text(series.name)
    39|                        .font(.aetherTitle)
    40|                        .foregroundStyle(Color.aetherText)
    41|                    if let genre = series.genre {
    42|                        Text(genre)
    43|                            .font(.aetherCaption)
    44|                            .foregroundStyle(.secondary)
    45|                    }
    46|                    if let plot = series.plot {
    47|                        Text(plot)
    48|                            .font(.aetherCaption)
    49|                            .foregroundStyle(.secondary)
    50|                            .lineLimit(4)
    51|                    }
    52|                }
    53|                Spacer()
    54|                Button("Done") { dismiss() }
    55|                    .keyboardShortcut(.cancelAction)
    56|            }
    57|            .padding()
    58|
    59|            Divider()
    60|
    61|            if isLoading {
    62|                ProgressView("Loading episodes…")
    63|                    .frame(maxWidth: .infinity, maxHeight: .infinity)
    64|            } else if let info {
    65|                let seasons = info.episodes.keys.sorted { Int($0) ?? 0 < Int($1) ?? 0 }
    66|                Picker("Season", selection: $selectedSeason) {
    67|                    ForEach(seasons, id: \.self) { s in
    68|                        Text("Season \(s)").tag(s)
    69|                    }
    70|                }
    71|                .pickerStyle(.segmented)
    72|                .padding(.horizontal)
    73|                .padding(.vertical, 8)
    74|
    75|                let episodes = (info.episodes[selectedSeason] ?? [])
    76|                    .sorted { $0.episodeNum < $1.episodeNum }
    77|
    78|                List(episodes) { ep in
    79|                    HStack {
    80|                        VStack(alignment: .leading, spacing: 2) {
    81|                            Text("E\(ep.episodeNum)  \(ep.title)")
    82|                                .font(.aetherBody)
    83|                                .foregroundStyle(Color.aetherText)
    84|                            if let plot = ep.info?.plot {
    85|                                Text(plot)
    86|                                    .font(.aetherCaption)
    87|                                    .foregroundStyle(.secondary)
    88|                                    .lineLimit(2)
    89|                            }
    90|                        }
    91|                        Spacer()
    92|                        Button("▶ Play") {
    93|                            playEpisode(ep)
    94|                            dismiss()
    95|                        }
    96|                        .buttonStyle(.borderedProminent)
    97|                        .tint(Color.aetherPrimary)
    98|                    }
    99|                    .padding(.vertical, 4)
   100|                }
   101|                .onAppear {
   102|                    if let first = seasons.first { selectedSeason = first }
   103|                }
   104|            }
   105|        }
   106|        .frame(minWidth: 560, minHeight: 420)
   107|        .background(Color.aetherBackground)
   108|        .task { await loadInfo() }
   109|    }
   110|
   111|    private func loadInfo() async {
   112|        isLoading = true
   113|        defer { isLoading = false }
   114|        info = try? await service.seriesInfo(seriesID: series.id)
   115|    }
   116|
   117|    private func playEpisode(_ ep: XstreamEpisode) {
   118|        let ext = ep.containerExtension ?? "mp4"
   119|        let url = credentials.baseURL
   120|            .appendingPathComponent("series")
   121|            .appendingPathComponent(credentials.username)
   122|            .appendingPathComponent(credentials.password)
   123|            .appendingPathComponent("\(ep.id).\(ext)")
   124|
   125|        let channel = Channel(
   126|            id: UUID(),
   127|            name: "\(series.name) — S\(ep.season)E\(ep.episodeNum) \(ep.title)",
   128|            streamURL: url,
   129|            logoURL: series.cover.flatMap(URL.init(string:)),
   130|            groupTitle: "Series",
   131|            epgId: nil
   132|        )
   133|        Task { @MainActor in
   134|            player.play(channel)
   135|        }
   136|    }
   137|}
   138|