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
            // Logo
            AsyncImage(url: channel.logoURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "tv")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                if let title = epgTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
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
