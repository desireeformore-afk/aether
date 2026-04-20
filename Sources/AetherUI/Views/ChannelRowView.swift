import SwiftUI
import AetherCore

/// A single row showing channel logo, name, and EPG info.
/// Works on macOS, iOS, and tvOS.
public struct ChannelRowView: View {
    public let channel: Channel
    public let isSelected: Bool
    public var epgTitle: String? = nil

    public init(channel: Channel, isSelected: Bool, epgTitle: String? = nil) {
        self.channel = channel
        self.isSelected = isSelected
        self.epgTitle = epgTitle
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Logo — circular, 40x40
            AsyncImage(url: channel.logoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "tv")
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .font(.system(size: 16))
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                if let title = epgTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var description = channel.name
        if let title = epgTitle {
            description += ", now playing: \(title)"
        }
        if isSelected {
            description += ", currently selected"
        }
        return description
    }
}
