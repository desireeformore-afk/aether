     1|import SwiftUI
     2|import AetherCore
     3|
     4|/// VOD browser sheet — shown when a playlist uses Xtream Codes and has VOD available.
     5|struct VODBrowserView: View {
     6|    let credentials: XstreamCredentials
     7|    @Bindable var player: PlayerCore
     8|
     9|    @State private var categories: [XstreamCategory] = []
    10|    @State private var streams: [XstreamVOD] = []
    11|    @State private var selectedCategory: XstreamCategory?
    12|    @State private var isLoadingCategories = false
    13|    @State private var isLoadingStreams = false
    14|    @State private var searchText = ""
    15|    @State private var selectedVOD: XstreamVOD?
    16|
    17|    private let service: XstreamService
    18|
    19|    init(credentials: XstreamCredentials, player: PlayerCore) {
    20|        self.credentials = credentials
    21|        self.player = player
    22|        self.service = XstreamService(credentials: credentials)
    23|    }
    24|
    25|    @Environment(\.dismiss) private var dismiss
    26|
    27|    var body: some View {
    28|        NavigationSplitView {
    29|            categoryList
    30|        } detail: {
    31|            vodGrid
    32|        }
    33|        .navigationTitle("VOD Browser")
    34|        .frame(minWidth: 720, minHeight: 500)
    35|        .toolbar {
    36|            ToolbarItem(placement: .cancellationAction) {
    37|                Button("Close") { dismiss() }
    38|                    .keyboardShortcut(.cancelAction)
    39|            }
    40|        }
    41|        .task { await loadCategories() }
    42|        .sheet(item: $selectedVOD) { vod in
    43|            VODDetailSheet(vod: vod, credentials: credentials, player: player)
    44|        }
    45|    }
    46|
    47|    // MARK: - Category list
    48|
    49|    private var categoryList: some View {
    50|        List(selection: $selectedCategory) {
    51|            if isLoadingCategories {
    52|                ProgressView("Loading categories…")
    53|            } else {
    54|                ForEach(categories) { cat in
    55|                    Text(cat.name)
    56|                        .font(.aetherBody)
    57|                        .tag(cat)
    58|                }
    59|            }
    60|        }
    61|        .navigationTitle("Categories")
    62|        .onChange(of: selectedCategory) { _, cat in
    63|            guard let cat else { return }
    64|            Task { await loadStreams(for: cat) }
    65|        }
    66|    }
    67|
    68|    // MARK: - VOD grid
    69|
    70|    private var vodGrid: some View {
    71|        Group {
    72|            if isLoadingStreams {
    73|                ProgressView("Loading titles…")
    74|                    .frame(maxWidth: .infinity, maxHeight: .infinity)
    75|            } else if filteredStreams.isEmpty && selectedCategory != nil {
    76|                ContentUnavailableView("No Titles", systemImage: "film")
    77|                    .frame(maxWidth: .infinity, maxHeight: .infinity)
    78|            } else if selectedCategory == nil {
    79|                ContentUnavailableView(
    80|                    "Pick a Category",
    81|                    systemImage: "rectangle.stack.fill",
    82|                    description: Text("Select a category from the sidebar.")
    83|                )
    84|                .frame(maxWidth: .infinity, maxHeight: .infinity)
    85|            } else {
    86|                ScrollView {
    87|                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
    88|                        ForEach(filteredStreams) { vod in
    89|                            VODCard(vod: vod)
    90|                                .onTapGesture { selectedVOD = vod }
    91|                        }
    92|                    }
    93|                    .padding()
    94|                }
    95|                .searchable(text: $searchText, prompt: "Search titles")
    96|            }
    97|        }
    98|        .background(Color.aetherBackground)
    99|    }
   100|
   101|    private var filteredStreams: [XstreamVOD] {
   102|        guard !searchText.isEmpty else { return streams }
   103|        return streams.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
   104|    }
   105|
   106|    // MARK: - Data loading
   107|
   108|    private func loadCategories() async {
   109|        isLoadingCategories = true
   110|        defer { isLoadingCategories = false }
   111|        do {
   112|            categories = try await service.vodCategories()
   113|        } catch {
   114|            // silent — categories list stays empty
   115|        }
   116|    }
   117|
   118|    private func loadStreams(for category: XstreamCategory) async {
   119|        streams = []
   120|        isLoadingStreams = true
   121|        defer { isLoadingStreams = false }
   122|        do {
   123|            streams = try await service.vodStreams(categoryID: category.id)
   124|        } catch {
   125|            // silent
   126|        }
   127|    }
   128|}
   129|
   130|// MARK: - VODCard
   131|
   132|private struct VODCard: View {
   133|    let vod: XstreamVOD
   134|
   135|    var body: some View {
   136|        VStack(alignment: .leading, spacing: 6) {
   137|            AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
   138|                switch phase {
   139|                case .success(let img):
   140|                    img.resizable().scaledToFill()
   141|                case .failure, .empty:
   142|                    ZStack {
   143|                        Color.aetherSurface
   144|                        Image(systemName: "film")
   145|                            .font(.largeTitle)
   146|                            .foregroundStyle(.secondary)
   147|                    }
   148|                @unknown default:
   149|                    Color.aetherSurface
   150|                }
   151|            }
   152|            .frame(width: 140, height: 200)
   153|            .clipShape(RoundedRectangle(cornerRadius: 8))
   154|
   155|            Text(vod.name)
   156|                .font(.aetherCaption)
   157|                .foregroundStyle(Color.aetherText)
   158|                .lineLimit(2)
   159|                .frame(width: 140, alignment: .leading)
   160|        }
   161|    }
   162|}
   163|
   164|// MARK: - VODDetailSheet
   165|
   166|private struct VODDetailSheet: View {
   167|    let vod: XstreamVOD
   168|    let credentials: XstreamCredentials
   169|    @Bindable var player: PlayerCore
   170|    @Environment(\.dismiss) private var dismiss
   171|
   172|    var body: some View {
   173|        VStack(spacing: 16) {
   174|            HStack(alignment: .top, spacing: 16) {
   175|                AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
   176|                    if case .success(let img) = phase {
   177|                        img.resizable().scaledToFill()
   178|                    } else {
   179|                        Color.aetherSurface
   180|                    }
   181|                }
   182|                .frame(width: 100, height: 150)
   183|                .clipShape(RoundedRectangle(cornerRadius: 8))
   184|
   185|                VStack(alignment: .leading, spacing: 8) {
   186|                    Text(vod.name)
   187|                        .font(.aetherTitle)
   188|                        .foregroundStyle(Color.aetherText)
   189|                    if let rating = vod.rating, !rating.isEmpty {
   190|                        Label("Rating: \(rating)", systemImage: "star.fill")
   191|                            .font(.aetherCaption)
   192|                            .foregroundStyle(.secondary)
   193|                    }
   194|                    Spacer()
   195|                    Button("▶  Play Now") {
   196|                        playVOD()
   197|                        dismiss()
   198|                    }
   199|                    .buttonStyle(.borderedProminent)
   200|                    .tint(Color.aetherPrimary)
   201|                }
   202|            }
   203|            .padding()
   204|
   205|            Button("Cancel", role: .cancel) { dismiss() }
   206|                .keyboardShortcut(.cancelAction)
   207|        }
   208|        .frame(width: 360)
   209|        .padding()
   210|        .background(Color.aetherBackground)
   211|    }
   212|
   213|    private func playVOD() {
   214|        // Build stream URL: baseURL/movie/user/pass/streamID.ext
   215|        let ext = vod.containerExtension ?? "mp4"
   216|        let streamURL = credentials.baseURL
   217|            .appendingPathComponent("movie")
   218|            .appendingPathComponent(credentials.username)
   219|            .appendingPathComponent(credentials.password)
   220|            .appendingPathComponent("\(vod.id).\(ext)")
   221|
   222|        let channel = Channel(
   223|            id: UUID(),
   224|            name: vod.name,
   225|            streamURL: streamURL,
   226|            logoURL: vod.streamIcon.flatMap(URL.init(string:)),
   227|            groupTitle: "VOD",
   228|            epgId: nil
   229|        )
   230|        Task { @MainActor in
   231|            player.play(channel)
   232|        }
   233|    }
   234|}
   235|