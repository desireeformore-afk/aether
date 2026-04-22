import SwiftUI
import AetherCore

struct StreamingServiceDetailView: View {
    let title: String
    let items: [ShelfItem]
    @Bindable var player: PlayerCore
    let credentials: XstreamCredentials
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVOD: XstreamVOD?

    let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 14)]

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(items.count) tytułów")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(.sRGB, red: 0.08, green: 0.08, blue: 0.08))

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(items) { item in
                            PosterCard(
                                title: item.title,
                                imageURL: item.imageURL,
                                onTap: {
                                    if let vod = item.vod {
                                        selectedVOD = vod
                                    }
                                }
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .sheet(item: $selectedVOD) { vod in
            VODDetailView(vod: vod, credentials: credentials, player: player)
        }
    }
}
