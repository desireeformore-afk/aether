import SwiftUI
import AetherCore
import AetherUI

// MARK: - ChannelGridView

struct ChannelGridView: View {
    let channels: [Channel]
    let selectedChannel: Channel?
    let onSelect: (Channel) -> Void
    let nowPlaying: [String: EPGEntry]

    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 12)
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

// MARK: - ChannelGridCell

struct ChannelGridCell: View {
    let channel: Channel
    let isSelected: Bool
    let epgEntry: EPGEntry?
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                // Card background
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color(.sRGB, red: 0.14, green: 0.14, blue: 0.16, opacity: 1))

                // Logo top-center
                VStack(spacing: 0) {
                    ChannelLogoView(url: channel.logoURL, size: 44, channelName: channel.name)
                        .padding(.top, 10)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Playing indicator top-right
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                        }
                        Spacer()
                    }
                }

                // Bottom gradient + channel name + EPG
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 36)

                    VStack(alignment: .center, spacing: 2) {
                        Text(channel.name)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let entry = epgEntry {
                            Text(entry.title)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 7)
                    .padding(.top, 3)
                    .background(.black.opacity(0.72))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .shadow(color: .black.opacity(isHovering ? 0.5 : 0), radius: 12, y: 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - ChannelViewMode

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
