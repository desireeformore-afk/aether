import SwiftUI
import AetherCore

/// VOD browser — shown when a playlist uses Xtream Codes and has VOD available.
struct VODBrowserView: View {
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    var isEmbedded: Bool = false

    @State private var categories: [XstreamCategory] = []
    @State private var allStreams: [XstreamVOD] = []
    @State private var streamsByCategory: [String: [XstreamVOD]] = [:]
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

    // MARK: - Embedded layout

    private var embeddedLayout: some View {
        HStack(spacing: 0) {
            // Category rail
            VStack(spacing: 0) {
                Text("Categories")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                Divider()

                if isLoadingCategories {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedCategory) {
                        ForEach(categories) { cat in
                            Text(cat.name)
                                .font(.system(size: 12))
                                .lineLimit(2)
                                .tag(cat)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(width: 140)
            .background(Color.aetherSurface)
            .onChange(of: selectedCategory) { _, cat in
                guard let cat else { return }
                Task { await loadStreams(for: cat) }
            }

            Divider()

            // Content area
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search VOD…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.aetherSurface)

                Divider()

                vodGridContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadCategories() }
        .sheet(item: $selectedVOD) { vod in
            VODDetailSheet(vod: vod, credentials: credentials, player: player)
        }
    }

    // MARK: - Category list (standalone)

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

    // MARK: - VOD grid (standalone)

    private var vodGrid: some View {
        vodGridContent
            .searchable(text: $searchText, prompt: "Search VOD")
    }

    // MARK: - VOD grid content (Netflix-style sections)

    private var vodGridContent: some View {
        Group {
            if isLoadingStreams {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedStreams.isEmpty && selectedCategory == nil && searchText.isEmpty {
                ContentUnavailableView(
                    "Select a category",
                    systemImage: "film",
                    description: Text("Choose a category on the left")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedStreams.isEmpty {
                ContentUnavailableView(
                    "No VOD content",
                    systemImage: "film",
                    description: Text("No streams match your search")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                netflixGrid
            }
        }
    }

    private var netflixGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                if !searchText.isEmpty {
                    // Flat grid when searching
                    sectionBlock(title: "Results", streams: displayedStreams)
                } else if selectedCategory != nil {
                    // Single-category view
                    sectionBlock(title: selectedCategory?.name ?? "", streams: displayedStreams)
                } else {
                    // All categories with section headers
                    ForEach(categories) { cat in
                        if let streams = streamsByCategory[cat.id], !streams.isEmpty {
                            sectionBlock(title: cat.name, streams: streams)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func sectionBlock(title: String, streams: [XstreamVOD]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Netflix-style section header
            HStack {
                Text(title)
                    .font(.system(.title3, design: .default, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(streams.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(Color.aetherPrimary)
                .frame(height: 2)
                .frame(maxWidth: 40)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                spacing: 16
            ) {
                ForEach(streams) { vod in
                    VODCard(vod: vod)
                        .onTapGesture { selectedVOD = vod }
                }
            }
        }
    }

    // MARK: - Filtered streams

    private var displayedStreams: [XstreamVOD] {
        let base: [XstreamVOD]
        if let cat = selectedCategory {
            base = streamsByCategory[cat.id] ?? []
        } else if !streamsByCategory.isEmpty {
            base = categories.flatMap { streamsByCategory[$0.id] ?? [] }
        } else {
            base = allStreams
        }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
            let fetched = try await service.vodStreams(categoryID: category.id)
            streamsByCategory[category.id] = fetched
            allStreams = categories.flatMap { streamsByCategory[$0.id] ?? [] }
        } catch {
            print("Failed to load VOD streams: \(error)")
        }
    }
}

// MARK: - VODCard

struct VODCard: View {
    let vod: XstreamVOD
    @State private var isHovered = false

    private let cardWidth: CGFloat = 160
    private var cardHeight: CGFloat { cardWidth * 3 / 2 }  // 2:3 ratio

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
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Hover overlay with gradient, title, rating
            if isHovered {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()

                    // Rating badge
                    if let rating = vod.rating, !rating.isEmpty, let ratingValue = Double(rating), ratingValue > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text(String(format: "%.1f", ratingValue))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.65))
                        .clipShape(Capsule())
                    }

                    Text(vod.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(10)
                .frame(width: cardWidth, height: cardHeight, alignment: .bottomLeading)
                .background(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.5), location: 0.55),
                            .init(color: .black.opacity(0.9), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .transition(.opacity)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.4 : 0), radius: 12, y: 6)
        .animation(.easeInOut(duration: 0.18), value: isHovered)
        .onHover { isHovered = $0 }
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
                        .white.opacity(0.25),
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

struct VODDetailSheet: View {
    let vod: XstreamVOD
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Large poster (2:3)
            AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    ZStack {
                        Color.aetherSurface
                        Image(systemName: "film")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 140, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Info + actions
            VStack(alignment: .leading, spacing: 12) {
                Text(vod.name)
                    .font(.system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if let rating = vod.rating, !rating.isEmpty, let ratingValue = Double(rating), ratingValue > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 14))
                        Text(String(format: "%.1f", ratingValue))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                Button {
                    playVOD()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Play Now")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)

                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 420, height: 270)
        .background(Color.aetherBackground)
    }

    private func playVOD() {
        let channel = vod.toChannel(credentials: credentials)
        Task { @MainActor in
            player.play(channel)
        }
    }
}
