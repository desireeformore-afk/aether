import SwiftUI
import AetherCore

struct SeriesBrowserView: View {
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore

    @State private var categories: [XstreamSeriesCategory] = []
    @State private var seriesList: [XstreamSeries] = []
    @State private var selectedCategory: XstreamSeriesCategory?
    @State private var isLoadingCategories = false
    @State private var isLoadingList = false
    @State private var searchText = ""
    @State private var selectedSeries: XstreamSeries?

    private let service: XstreamService

    init(credentials: XstreamCredentials, player: PlayerCore) {
        self.credentials = credentials
        self.player = player
        self.service = XstreamService(credentials: credentials)
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationSplitView {
            categoryList
        } detail: {
            seriesGrid
        }
        .navigationTitle("Series")
        .frame(minWidth: 720, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .task { await loadCategories() }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series, credentials: credentials, player: player)
        }
    }

    private var categoryList: some View {
        List(selection: $selectedCategory) {
            if isLoadingCategories {
                ProgressView("Loading categories…")
            } else {
                ForEach(categories) { cat in
                    Text(cat.name)
                        .font(.aetherBody)
                        .tag(cat)
                }
            }
        }
        .navigationTitle("Categories")
        .onChange(of: selectedCategory) { _, cat in
            guard let cat else { return }
            Task { await loadList(for: cat) }
        }
    }

    private var seriesGrid: some View {
        Group {
            if isLoadingList {
                ProgressView("Loading series…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredList.isEmpty && selectedCategory != nil {
                ContentUnavailableView("No Series", systemImage: "tv")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedCategory == nil {
                ContentUnavailableView(
                    "Pick a Category",
                    systemImage: "rectangle.stack.fill",
                    description: Text("Select a category from the sidebar.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                        ForEach(filteredList) { series in
                            SeriesCard(series: series)
                                .onTapGesture { selectedSeries = series }
                        }
                    }
                    .padding()
                }
                .searchable(text: $searchText, prompt: "Search series")
            }
        }
        .background(Color.aetherBackground)
    }

    private var filteredList: [XstreamSeries] {
        guard !searchText.isEmpty else { return seriesList }
        return seriesList.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func loadCategories() async {
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        categories = (try? await service.seriesCategories()) ?? []
    }

    private func loadList(for category: XstreamSeriesCategory) async {
        seriesList = []
        isLoadingList = true
        defer { isLoadingList = false }
        seriesList = (try? await service.seriesList(categoryID: category.id)) ?? []
    }
}

// MARK: - SeriesCard

private struct SeriesCard: View {
    let series: XstreamSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure, .empty:
                    ZStack {
                        Color.aetherSurface
                        Image(systemName: "tv")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color.aetherSurface
                }
            }
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(series.name)
                .font(.aetherCaption)
                .foregroundStyle(Color.aetherText)
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)
        }
    }
}
