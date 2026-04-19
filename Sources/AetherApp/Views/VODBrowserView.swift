import SwiftUI
import AetherCore

/// VOD browser sheet — shown when a playlist uses Xtream Codes and has VOD available.
struct VODBrowserView: View {
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    var isEmbedded: Bool = false

    @State private var categories: [XstreamCategory] = []
    @State private var streams: [XstreamVOD] = []
    @State private var selectedCategory: XstreamCategory?
    @State private var isLoadingCategories = false
    @State private var isLoadingStreams = false
    @State private var searchText = ""
    @State private var selectedVOD: XstreamVOD?

    private let service: XstreamService

    init(credentials: XstreamCredentials, player: PlayerCore, isEmbedded: Bool = false) {
        self.credentials = credentials
        self.player = player
        self.isEmbedded = isEmbedded
        self.service = XstreamService(credentials: credentials)
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if isEmbedded {
            embeddedLayout
        } else {
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
    }

    // Inline layout for panel embedding
    private var embeddedLayout: some View {
        HSplitView {
            // Category rail
            List(selection: $selectedCategory) {
                if isLoadingCategories {
                    ProgressView()
                } else {
                    ForEach(categories) { cat in
                        Text(cat.name)
                            .font(.system(size: 12))
                            .tag(cat)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 120, maxWidth: 150)
            .onChange(of: selectedCategory) { _, cat in
                guard let cat else { return }
                Task { await loadStreams(for: cat) }
            }

            vodGrid
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
                ProgressView("Loading streams…")
            } else if filteredStreams.isEmpty {
                ContentUnavailableView(
                    "No VOD content",
                    systemImage: "film",
                    description: Text("Select a category to browse")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(filteredStreams) { vod in
                            VODCard(vod: vod)
                                .onTapGesture {
                                    selectedVOD = vod
                                }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search VOD")
    }

    private var filteredStreams: [XstreamVOD] {
        if searchText.isEmpty {
            return streams
        }
        return streams.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Data loading

    private func loadCategories() async {
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        do {
            categories = try await service.vodCategories()
        } catch {
            print("Failed to load VOD categories: \(error)")
        }
    }

    private func loadStreams(for category: XstreamCategory) async {
        isLoadingStreams = true
        defer { isLoadingStreams = false }
        do {
            streams = try await service.vodStreams(categoryID: category.id)
        } catch {
            print("Failed to load VOD streams: \(error)")
        }
    }
}

// MARK: - VODCard

private struct VODCard: View {
    let vod: XstreamVOD
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Poster image
            AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .empty:
                    ShimmerView()
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
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
            .frame(width: 160, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Hover overlay
            if isHovered {
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    
                    HStack(spacing: 4) {
                        if let rating = vod.rating, !rating.isEmpty, let ratingValue = Double(rating) {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                Text(String(format: "%.1f", ratingValue))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())
                        }
                        

                        
                        Spacer()
                    }
                    
                    Text(vod.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
                .frame(width: 160, height: 240, alignment: .bottom)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

}

// MARK: - ShimmerView

private struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.aetherSurface
                
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.3),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * geometry.size.width * 2 - geometry.size.width)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - VODDetailSheet

private struct VODDetailSheet: View {
    let vod: XstreamVOD
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
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
