import SwiftUI
import AetherCore

/// VOD browser sheet — shown when a playlist uses Xtream Codes and has VOD available.
struct VODBrowserView: View {
    let credentials: XstreamCredentials
    @ObservedObject var player: PlayerCore

    @State private var categories: [XstreamCategory] = []
    @State private var streams: [XstreamVOD] = []
    @State private var selectedCategory: XstreamCategory?
    @State private var isLoadingCategories = false
    @State private var isLoadingStreams = false
    @State private var searchText = ""
    @State private var selectedVOD: XstreamVOD?

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
            vodGrid
        }
        .navigationTitle("VOD Browser")
        .frame(minWidth: 720, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .task { await loadCategories() }
        .sheet(item: $selectedVOD) { vod in
            VODDetailSheet(vod: vod, credentials: credentials, player: player)
        }
    }

    // MARK: - Category list

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
            Task { await loadStreams(for: cat) }
        }
    }

    // MARK: - VOD grid

    private var vodGrid: some View {
        Group {
            if isLoadingStreams {
                ProgressView("Loading titles…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredStreams.isEmpty && selectedCategory != nil {
                ContentUnavailableView("No Titles", systemImage: "film")
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
                        ForEach(filteredStreams) { vod in
                            VODCard(vod: vod)
                                .onTapGesture { selectedVOD = vod }
                        }
                    }
                    .padding()
                }
                .searchable(text: $searchText, prompt: "Search titles")
            }
        }
        .background(Color.aetherBackground)
    }

    private var filteredStreams: [XstreamVOD] {
        guard !searchText.isEmpty else { return streams }
        return streams.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Data loading

    private func loadCategories() async {
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            categories = try await service.vodCategories()
        } catch {
            // silent — categories list stays empty
        }
    }

    private func loadStreams(for category: XstreamCategory) async {
        streams = []
        isLoadingStreams = true
        defer { isLoadingStreams = false }
        do {
            streams = try await service.vodStreams(categoryID: category.id)
        } catch {
            // silent
        }
    }
}

// MARK: - VODCard

private struct VODCard: View {
    let vod: XstreamVOD

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure, .empty:
                    ZStack {
                        Color.aetherSurface
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color.aetherSurface
                }
            }
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(vod.name)
                .font(.aetherCaption)
                .foregroundStyle(Color.aetherText)
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)
        }
    }
}

// MARK: - VODDetailSheet

private struct VODDetailSheet: View {
    let vod: XstreamVOD
    let credentials: XstreamCredentials
    @ObservedObject var player: PlayerCore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Color.aetherSurface
                    }
                }
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    Text(vod.name)
                        .font(.aetherTitle)
                        .foregroundStyle(Color.aetherText)
                    if let rating = vod.rating, !rating.isEmpty {
                        Label("Rating: \(rating)", systemImage: "star.fill")
                            .font(.aetherCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("▶  Play Now") {
                        playVOD()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.aetherPrimary)
                }
            }
            .padding()

            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .frame(width: 360)
        .padding()
        .background(Color.aetherBackground)
    }

    private func playVOD() {
        // Build stream URL: baseURL/movie/user/pass/streamID.ext
        let ext = vod.containerExtension ?? "mp4"
        let streamURL = credentials.baseURL
            .appendingPathComponent("movie")
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(vod.id).\(ext)")

        let channel = Channel(
            id: UUID(),
            name: vod.name,
            streamURL: streamURL,
            logoURL: vod.streamIcon.flatMap(URL.init(string:)),
            groupTitle: "VOD",
            epgId: nil
        )
        Task { @MainActor in
            player.play(channel)
        }
    }
}
