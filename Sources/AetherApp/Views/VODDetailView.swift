import SwiftUI
import SwiftData
import AetherCore

// MARK: - VODDetailView

struct VODDetailView: View {
    let item: ShelfItem
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SubtitleStore.self) private var subtitleStore

    @State private var selectedVOD: XstreamVOD?
    @State private var tmdbMedia: TMDBMedia? = nil
    @State private var backdropURL: URL? = nil
    @State private var posterURL: URL? = nil
    @State private var isHoveringPoster = false

    init(item: ShelfItem, credentials: XstreamCredentials, player: PlayerCore) {
        self.item = item
        self.credentials = credentials
        self.player = player
        _selectedVOD = State(initialValue: item.vod ?? item.alternateVODs.first)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Ambient Backdrop Layer
            if let url = backdropURL {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                           .blur(radius: 12)  // Crisper cinematic blur
                           .scaleEffect(1.05) // Prevent edge bleeding
                    } else if case .empty = phase {
                        Color(.sRGB, red: 0.05, green: 0.05, blue: 0.07, opacity: 1)
                    }
                }
                .frame(width: 680, height: 420)
                .clipped()
            } else {
                AsyncImage(url: selectedVOD?.streamIcon.flatMap(URL.init(string:))) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                           .blur(radius: 40)
                           .scaleEffect(1.2)
                    }
                }
                .frame(width: 680, height: 420)
                .clipped()
            }
            
            // Glassmorphism Frosting
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            
            // Content Shadow Overlay for contrast
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .trailing, endPoint: .leading)

            HStack(spacing: 0) {
                posterPanel
                infoPanel
            }
            dismissButton
        }
        .frame(width: 680, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 15)
        .task(id: item.title) {
            do {
                if let media = try await TMDBClient.shared.search(title: item.title, type: .movie) {
                    let bURL = await TMDBClient.shared.backdropURL(for: media.backdropPath)
                    let pURL = await TMDBClient.shared.posterURL(for: media.posterPath)
                    await MainActor.run {
                        self.tmdbMedia = media
                        self.backdropURL = bURL
                        self.posterURL = pURL
                    }
                }
            } catch {
                print("[VODDetailView] TMDB fetch failed: \(error)")
            }
        }
    }

    // MARK: - Poster

    private var posterPanel: some View {
        AsyncImage(url: posterURL ?? selectedVOD?.streamIcon.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            default:
                ZStack {
                    Color(.sRGB, red: 0.10, green: 0.10, blue: 0.13, opacity: 1)
                    Image(systemName: "film")
                        .font(.system(size: 52))
                        .foregroundStyle(.white.opacity(0.15))
                }
            }
        }
        .frame(width: 240, height: 420)
        .clipped()
        // Apple TV style popup hover
        .scaleEffect(isHoveringPoster ? 1.03 : 1.0)
        .shadow(color: isHoveringPoster ? .white.opacity(0.15) : .clear, radius: 20, x: 0, y: 10)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isHoveringPoster)
        .onHover { isHoveringPoster = $0 }
    }

    // MARK: - Info panel

    private var infoPanel: some View {
        ZStack {
            Color.clear

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 40)

                if !item.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(item.tags).sorted(by: { $0.rawValue < $1.rawValue })) { tag in
                            Text(tag.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(tag.isResolution ? .black : .white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(tag.isResolution ? Color(.sRGB, red: 0.85, green: 0.7, blue: 0.3, opacity: 1) : Color.white.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.bottom, 8)
                }

                Text(item.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                metadataRow
                    .padding(.top, 12)

                if item.alternateVODs.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wybierz wersję")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        Picker("", selection: $selectedVOD) {
                            ForEach(item.alternateVODs) { altVod in
                                Text(altVod.name).tag(Optional(altVod))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 300)
                    }
                    .padding(.top, 20)
                }

                Spacer()

                playButton

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let year = tmdbMedia?.yearString {
                Text(year)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            
            if let cat = selectedVOD?.categoryName, !cat.isEmpty {
                if tmdbMedia?.yearString != nil {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 4, height: 4)
                }
                
                Text(cat)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Fallback to Xtream rating if TMDB hasn't provided one
            let finalRating = tmdbMedia?.voteAverage ?? (selectedVOD?.rating.flatMap { Double($0) } ?? 0)
            
            if finalRating > 0 {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 4, height: 4)
                    
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                    
                    Text(String(format: "%.1f", finalRating))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    
                    if tmdbMedia != nil {
                        Text("TMDB")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .foregroundStyle(.yellow)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
        }
    }

    private var playButton: some View {
        HStack(spacing: 12) {
            Button {
                guard let selectedVOD else { return }
                var ch = selectedVOD.toChannel(credentials: credentials)
                ch.availableVariants = item.alternateVODs.map { $0.toChannel(credentials: credentials) }
                Task { @MainActor in player.play(ch) }
                subtitleStore.search(for: selectedVOD.name)
                dismiss()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Odtwórz")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(selectedVOD == nil)

            Button { toggleVODFavorite() } label: {
                Image(systemName: isVODFavorited ? "star.fill" : "star")
                    .font(.system(size: 22))
                    .foregroundStyle(isVODFavorited ? .yellow : .secondary)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .help(isVODFavorited ? "Remove from Favorites" : "Add to Favorites")
        }
    }

    private var vodDeterministicID: UUID {
        guard let selectedVOD else { return UUID() }
        let offset = selectedVOD.id + 0xE00000000000
        return UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", offset))") ?? UUID()
    }

    private var isVODFavorited: Bool {
        guard selectedVOD != nil else { return false }
        let fav = vodDeterministicID
        let matching = (try? modelContext.fetch(
            FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.channelID == fav })
        )) ?? []
        return !matching.isEmpty
    }

    private func toggleVODFavorite() {
        guard let selectedVOD else { return }
        let fav = vodDeterministicID
        let matching = (try? modelContext.fetch(
            FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.channelID == fav })
        )) ?? []
        if let existing = matching.first {
            modelContext.delete(existing)
        } else {
            let record = FavoriteRecord(
                itemID: fav,
                name: selectedVOD.name,
                streamURLString: selectedVOD.streamIcon ?? "",
                posterURLString: selectedVOD.streamIcon,
                contentType: "vod"
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
    }

    private var dismissButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.65))
                .shadow(color: .black.opacity(0.4), radius: 3)
        }
        .buttonStyle(.plain)
        .padding(14)
        .keyboardShortcut(.escape, modifiers: [])
    }
}
