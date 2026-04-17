import SwiftUI
import AetherCore

/// Horizontal scrollable EPG timeline for a single channel's today schedule.
/// Programme blocks are proportional to their duration (1 hour = 120 pt).
/// Auto-scrolls to the current time on appear; shows a red "now" indicator.
public struct EPGTimelineView: View {
    let entries: [EPGEntry]
    let channelID: String

    public static let pointsPerHour: CGFloat = 120
    private static let blockHeight: CGFloat = 56
    private static let timelineOffset: CGFloat = 40  // top ruler height

    @State private var selectedEntry: EPGEntry?
    @State private var showPopover = false

    public init(entries: [EPGEntry], channelID: String) {
        self.entries = entries
        self.channelID = channelID
    }

    // Offset (in points) of `date` from the first entry's start
    private func xOffset(for date: Date) -> CGFloat {
        guard let first = entries.first else { return 0 }
        let seconds = date.timeIntervalSince(first.start)
        return CGFloat(seconds / 3600) * Self.pointsPerHour
    }

    private var nowOffset: CGFloat { xOffset(for: Date()) }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Programme blocks
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            programmeBlock(for: entry)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, Self.timelineOffset)

                    // Hour ruler
                    hourRuler

                    // "Now" red indicator line
                    nowIndicator
                }
            }
            .frame(height: Self.blockHeight + Self.timelineOffset + 24)
            .onAppear {
                scrollToNow(proxy: proxy)
            }
            .onChange(of: channelID) { _, _ in
                scrollToNow(proxy: proxy)
            }
        }
    }

    // MARK: - Now indicator

    private var nowIndicator: some View {
        GeometryReader { _ in
            let x = nowOffset + 8  // +8 for horizontal padding
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color.red.opacity(0.85))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)

                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: -3)
            }
            .offset(x: x)
        }
    }

    // MARK: - Hour ruler

    private var hourRuler: some View {
        let hours = hourMarks()
        return ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { date in
                let x = xOffset(for: date) + 8
                VStack(alignment: .leading, spacing: 0) {
                    Text(date, style: .time)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .offset(x: x)
            }
        }
        .frame(height: Self.timelineOffset)
    }

    private func hourMarks() -> [Date] {
        guard let first = entries.first, let last = entries.last else { return [] }
        var marks: [Date] = []
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        var t = cal.nextDate(after: first.start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? first.start
        while t <= last.end {
            marks.append(t)
            t = t.addingTimeInterval(3600)
        }
        return marks
    }

    // MARK: - Scroll to now

    private func scrollToNow(proxy: ScrollViewProxy) {
        // find index of currently-airing entry
        if let idx = entries.firstIndex(where: { $0.isOnAir() }) {
            withAnimation(.easeInOut(duration: 0.4)) {
                proxy.scrollTo(idx, anchor: .leading)
            }
        }
    }

    // MARK: - Programme block

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
                        .stroke(isNow ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: isNow ? 1.5 : 0.5)
                )

            // Progress fill for currently airing
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
