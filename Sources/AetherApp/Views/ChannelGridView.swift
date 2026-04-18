import SwiftUI
import AetherCore

/// Grid view for channels with logo display.
struct ChannelGridView: View {
    let channels: [Channel]
    let selectedChannel: Channel?
    let onSelect: (Channel) -> Void
    let nowPlaying: [String: EPGEntry]

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(channels) { channel in
                    ChannelGridCell(
                        channel: channel,
                        isSelected: selectedChannel?.id == channel.id,
                        epgEntry: nowPlaying[channel.epgId ?? channel.name],
                        onSelect: { onSelect(channel) }
                    )
                }
            }
            .padding(12)
        }
    }
}

/// Individual channel cell in grid view.
struct ChannelGridCell: View {
    let channel: Channel
    let isSelected: Bool
    let epgEntry: EPGEntry?
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Channel logo
                ZStack {
                    if let logoURL = channel.logoURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            case .failure, .empty:
                                placeholderLogo
                            @unknown default:
                                placeholderLogo
                            }
                        }
                    } else {
                        placeholderLogo
                    }

                    // Playing indicator
                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .background(
                                        Circle()
                                            .fill(.black.opacity(0.5))
                                            .frame(width: 32, height: 32)
                                    )
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(height: 80)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Channel name
                Text(channel.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)

                // EPG info (on hover)
                if isHovering, let entry = epgEntry {
                    Text(entry.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    private var placeholderLogo: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "tv")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}

/// View mode for channel list.
enum ChannelViewMode: String, CaseIterable, Codable {
    case list = "list"
    case grid = "grid"

    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }

    var label: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        }
    }
}
