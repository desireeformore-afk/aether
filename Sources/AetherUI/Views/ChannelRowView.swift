import SwiftUI
import AetherCore

/// A single row showing channel logo, name, and EPG info.
/// Works on macOS, iOS, and tvOS.
public struct ChannelRowView: View {
    public let channel: Channel
    public let isSelected: Bool
    public var epgTitle: String? = nil
    public var epgProgress: Double? = nil

    public init(channel: Channel, isSelected: Bool, epgTitle: String? = nil, epgProgress: Double? = nil) {
        self.channel = channel
        self.isSelected = isSelected
        self.epgTitle = epgTitle
        self.epgProgress = epgProgress
    }

    public var body: some View {
        HStack(spacing: 12) {
            ChannelLogoView(url: channel.logoURL, size: 40, channelName: channel.name)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                if let title = epgTitle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                            .lineLimit(1)
                            
                        if let progress = epgProgress, progress >= 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.2))
                                        .frame(height: 3)
                                    
                                    Capsule()
                                        .fill(isSelected ? Color.white : Color.accentColor)
                                        .frame(width: max(0, min(1.0, CGFloat(progress))) * geo.size.width, height: 3)
                                }
                            }
                            .frame(height: 3)
                            .padding(.trailing, 20)
                        }
                    }
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
