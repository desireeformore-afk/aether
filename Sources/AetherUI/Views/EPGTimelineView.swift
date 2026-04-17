import SwiftUI
import AetherCore

/// Horizontal scrollable EPG timeline for a single channel's today schedule.
/// Programme blocks are proportional to their duration (1 hour = 120 pt).
public struct EPGTimelineView: View {
    let entries: [EPGEntry]
    let channelID: String

    private static let pointsPerHour: CGFloat = 120
    private static let blockHeight: CGFloat = 56

    @State private var selectedEntry: EPGEntry?
    @State private var showPopover = false

    public init(entries: [EPGEntry], channelID: String) {
        self.entries = entries
        self.channelID = channelID
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 2) {
                ForEach(entries) { entry in
                    programmeBlock(for: entry)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: Self.blockHeight + 20)
    }

    @ViewBuilder
    private func programmeBlock(for entry: EPGEntry) -> some View {
        let duration = entry.end.timeIntervalSince(entry.start)
        let width = max(60, CGFloat(duration / 3600) * Self.pointsPerHour)
        let isNow = entry.isOnAir()
        let progress = entry.progress()

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(isNow ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isNow ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isNow ? 1.5 : 0.5)
                )

            // Progress bar for currently airing
            if isNow && progress > 0 {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: geo.size.width * progress)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.caption2)
                    .fontWeight(isNow ? .semibold : .regular)
                    .foregroundStyle(isNow ? Color.primary : Color.secondary)
                    .lineLimit(2)

                Text(entry.start, style: .time)
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .frame(width: width, height: Self.blockHeight)
        #if os(tvOS)
        .focusable()
        #else
        .onTapGesture {
            selectedEntry = entry
            showPopover = true
        }
        .popover(isPresented: $showPopover) {
            if let e = selectedEntry {
                EPGProgrammePopover(entry: e)
            }
        }
        #endif
    }
}

// MARK: - Programme Detail Popover

private struct EPGProgrammePopover: View {
    let entry: EPGEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .font(.headline)

            Label {
                Text("\(entry.start, style: .time) – \(entry.end, style: .time)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            }

            if let desc = entry.description, !desc.isEmpty {
                Text(desc)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }

            if let cat = entry.category {
                Label(cat, systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(minWidth: 260, maxWidth: 340)
    }
}
