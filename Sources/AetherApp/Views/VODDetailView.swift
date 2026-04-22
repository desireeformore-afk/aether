import SwiftUI
import SwiftData
import AetherCore

// MARK: - VODDetailView

struct VODDetailView: View {
    let vod: XstreamVOD
    let credentials: XstreamCredentials
    @Bindable var player: PlayerCore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SubtitleStore.self) private var subtitleStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                posterPanel
                infoPanel
            }
            dismissButton
        }
        .frame(width: 680, height: 420)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Poster

    private var posterPanel: some View {
        AsyncImage(url: vod.streamIcon.flatMap(URL.init(string:))) { phase in
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
    }

    // MARK: - Info panel

    private var infoPanel: some View {
        ZStack {
            Color(.sRGB, red: 0.08, green: 0.08, blue: 0.11, opacity: 1)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 40)

                Text(vod.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                metadataRow
                    .padding(.top, 12)

                Spacer()

                playButton

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 10) {
            if let cat = vod.categoryName, !cat.isEmpty {
                Text(cat)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3, height: 3)
            }

            if let rating = vod.rating, !rating.isEmpty,
               let rv = Double(rating), rv > 0 {
                HStack(spacing: 3) {
                    let stars = max(0, min(5, Int((rv / 2).rounded())))
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < stars ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                    Text(String(format: "%.1f", rv))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    private var playButton: some View {
        HStack(spacing: 12) {
            Button {
                let ch = vod.toChannel(credentials: credentials)
                Task { @MainActor in player.play(ch) }
                subtitleStore.search(for: vod.name)
                dismiss()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Play")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

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
        let offset = vod.id + 0xE00000000000
        return UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", offset))") ?? UUID()
    }

    private var isVODFavorited: Bool {
        let fav = vodDeterministicID
        let matching = (try? modelContext.fetch(
            FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.channelID == fav })
        )) ?? []
        return !matching.isEmpty
    }

    private func toggleVODFavorite() {
        let fav = vodDeterministicID
        let matching = (try? modelContext.fetch(
            FetchDescriptor<FavoriteRecord>(predicate: #Predicate { $0.channelID == fav })
        )) ?? []
        if let existing = matching.first {
            modelContext.delete(existing)
        } else {
            let record = FavoriteRecord(
                itemID: fav,
                name: vod.name,
                streamURLString: vod.streamIcon ?? "",
                posterURLString: vod.streamIcon,
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
