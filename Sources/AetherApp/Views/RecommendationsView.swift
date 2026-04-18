import SwiftUI
import AetherCore

struct RecommendationsView: View {
    @Bindable var recommendationService: RecommendationService
    @Environment(PlayerCore.self) var playerCore

    var channels: [Channel]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recommended for You")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if recommendationService.isGenerating {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Button {
                    Task {
                        await recommendationService.generateRecommendations(for: channels)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh recommendations")
            }
            .padding()

            Divider()

            // Recommendations List
            if recommendationService.recommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No recommendations yet")
                        .foregroundColor(.secondary)
                    Text("Watch some channels to get personalized recommendations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Generate Recommendations") {
                        Task {
                            await recommendationService.generateRecommendations(for: channels)
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(recommendationService.recommendations) { recommendation in
                            RecommendationCard(
                                recommendation: recommendation,
                                channel: channels.first { $0.name == recommendation.channelName },
                                onPlay: {
                                    if let channel = channels.first(where: { $0.name == recommendation.channelName }) {
                                        playerCore.play(channel)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            if recommendationService.recommendations.isEmpty {
                Task {
                    await recommendationService.generateRecommendations(for: channels)
                }
            }
        }
    }
}

struct RecommendationCard: View {
    let recommendation: RecommendationService.ChannelRecommendation
    let channel: Channel?
    let onPlay: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Channel Logo or Placeholder
            if let logoURL = channel?.logoURL {
                AsyncImage(url: logoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "tv")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
                .frame(width: 60, height: 60)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Image(systemName: "tv")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                    .frame(width: 60, height: 60)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
            }

            // Channel Info
            VStack(alignment: .leading, spacing: 6) {
                Text(recommendation.channelName)
                    .font(.headline)

                HStack(spacing: 8) {
                    Image(systemName: reasonIcon)
                        .font(.caption)
                        .foregroundColor(reasonColor)

                    Text(recommendation.reason.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Score indicator
                HStack(spacing: 4) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < Int(recommendation.score * 5) ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
            }

            Spacer()

            // Play Button
            Button {
                onPlay()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1.0 : 0.7)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var reasonIcon: String {
        switch recommendation.reason {
        case .similarToFavorites:
            return "heart.fill"
        case .popularInCategory:
            return "chart.bar.fill"
        case .watchedSimilarChannels:
            return "eye.fill"
        case .timeOfDay:
            return "clock.fill"
        case .trending:
            return "flame.fill"
        case .newContent:
            return "sparkles"
        case .unwatched:
            return "star.fill"
        }
    }

    private var reasonColor: Color {
        switch recommendation.reason {
        case .similarToFavorites:
            return .red
        case .popularInCategory:
            return .blue
        case .watchedSimilarChannels:
            return .green
        case .timeOfDay:
            return .orange
        case .trending:
            return .pink
        case .newContent:
            return .purple
        case .unwatched:
            return .yellow
        }
    }
}
