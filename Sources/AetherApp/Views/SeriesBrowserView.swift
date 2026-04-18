     1|import SwiftUI
     2|import AetherCore
     3|
     4|struct SeriesBrowserView: View {
     5|    let credentials: XstreamCredentials
     6|    @Bindable var player: PlayerCore
     7|
     8|    @State private var categories: [XstreamSeriesCategory] = []
     9|    @State private var seriesList: [XstreamSeries] = []
    10|    @State private var selectedCategory: XstreamSeriesCategory?
    11|    @State private var isLoadingCategories = false
    12|    @State private var isLoadingList = false
    13|    @State private var searchText = ""
    14|    @State private var selectedSeries: XstreamSeries?
    15|
    16|    private let service: XstreamService
    17|
    18|    init(credentials: XstreamCredentials, player: PlayerCore) {
    19|        self.credentials = credentials
    20|        self.player = player
    21|        self.service = XstreamService(credentials: credentials)
    22|    }
    23|
    24|    @Environment(\.dismiss) private var dismiss
    25|
    26|    var body: some View {
    27|        NavigationSplitView {
    28|            categoryList
    29|        } detail: {
    30|            seriesGrid
    31|        }
    32|        .navigationTitle("Series")
    33|        .frame(minWidth: 720, minHeight: 500)
    34|        .toolbar {
    35|            ToolbarItem(placement: .cancellationAction) {
    36|                Button("Close") { dismiss() }
    37|                    .keyboardShortcut(.cancelAction)
    38|            }
    39|        }
    40|        .task { await loadCategories() }
    41|        .sheet(item: $selectedSeries) { series in
    42|            SeriesDetailView(series: series, credentials: credentials, player: player)
    43|        }
    44|    }
    45|
    46|    private var categoryList: some View {
    47|        List(selection: $selectedCategory) {
    48|            if isLoadingCategories {
    49|                ProgressView("Loading categories…")
    50|            } else {
    51|                ForEach(categories) { cat in
    52|                    Text(cat.name)
    53|                        .font(.aetherBody)
    54|                        .tag(cat)
    55|                }
    56|            }
    57|        }
    58|        .navigationTitle("Categories")
    59|        .onChange(of: selectedCategory) { _, cat in
    60|            guard let cat else { return }
    61|            Task { await loadList(for: cat) }
    62|        }
    63|    }
    64|
    65|    private var seriesGrid: some View {
    66|        Group {
    67|            if isLoadingList {
    68|                ProgressView("Loading series…")
    69|                    .frame(maxWidth: .infinity, maxHeight: .infinity)
    70|            } else if filteredList.isEmpty && selectedCategory != nil {
    71|                ContentUnavailableView("No Series", systemImage: "tv")
    72|                    .frame(maxWidth: .infinity, maxHeight: .infinity)
    73|            } else if selectedCategory == nil {
    74|                ContentUnavailableView(
    75|                    "Pick a Category",
    76|                    systemImage: "rectangle.stack.fill",
    77|                    description: Text("Select a category from the sidebar.")
    78|                )
    79|                .frame(maxWidth: .infinity, maxHeight: .infinity)
    80|            } else {
    81|                ScrollView {
    82|                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
    83|                        ForEach(filteredList) { series in
    84|                            SeriesCard(series: series)
    85|                                .onTapGesture { selectedSeries = series }
    86|                        }
    87|                    }
    88|                    .padding()
    89|                }
    90|                .searchable(text: $searchText, prompt: "Search series")
    91|            }
    92|        }
    93|        .background(Color.aetherBackground)
    94|    }
    95|
    96|    private var filteredList: [XstreamSeries] {
    97|        guard !searchText.isEmpty else { return seriesList }
    98|        return seriesList.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    99|    }
   100|
   101|    private func loadCategories() async {
   102|        isLoadingCategories = true
   103|        defer { isLoadingCategories = false }
   104|        categories = (try? await service.seriesCategories()) ?? []
   105|    }
   106|
   107|    private func loadList(for category: XstreamSeriesCategory) async {
   108|        seriesList = []
   109|        isLoadingList = true
   110|        defer { isLoadingList = false }
   111|        seriesList = (try? await service.seriesList(categoryID: category.id)) ?? []
   112|    }
   113|}
   114|
   115|// MARK: - SeriesCard
   116|
   117|private struct SeriesCard: View {
   118|    let series: XstreamSeries
   119|
   120|    var body: some View {
   121|        VStack(alignment: .leading, spacing: 6) {
   122|            AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
   123|                switch phase {
   124|                case .success(let img):
   125|                    img.resizable().scaledToFill()
   126|                case .failure, .empty:
   127|                    ZStack {
   128|                        Color.aetherSurface
   129|                        Image(systemName: "tv")
   130|                            .font(.largeTitle)
   131|                            .foregroundStyle(.secondary)
   132|                    }
   133|                @unknown default:
   134|                    Color.aetherSurface
   135|                }
   136|            }
   137|            .frame(width: 140, height: 200)
   138|            .clipShape(RoundedRectangle(cornerRadius: 8))
   139|
   140|            Text(series.name)
   141|                .font(.aetherCaption)
   142|                .foregroundStyle(Color.aetherText)
   143|                .lineLimit(2)
   144|                .frame(width: 140, alignment: .leading)
   145|        }
   146|    }
   147|}
   148|