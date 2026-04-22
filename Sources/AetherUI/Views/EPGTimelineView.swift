import SwiftUI
import AetherCore

/// Horizontal scrollable EPG timeline for a channel's schedule.
/// - Programme blocks are proportional to duration (1 hour = 120 pt).
/// - Auto-scrolls to the current time on appear.
/// - Shows a red "now" indicator line.
/// - Includes a day-selector (Today / Tomorrow) in the header.
/// - Shows an empty state when no EPG data is available.
public struct EPGTimelineView: View {
    /// All entries for this channel (can span multiple days; view filters by selectedDay).
    let allEntries: [EPGEntry]
    let channelID: String
    let channelName: String

    public static let pointsPerHour: CGFloat = 120
    private static let blockHeight: CGFloat = 56
    private static let timelineOffset: CGFloat = 40  // top ruler height

    @State private var selectedEntry: EPGEntry?
    @State private var showPopover = false
    @State private var selectedDay: DayOffset = .today
    /// Entry UUIDs that have a pending reminder notification.
    @State private var reminders: Set<UUID> = []

    public init(entries: [EPGEntry], channelID: String, channelName: String = "") {
        self.allEntries = entries
        self.channelID = channelID
        self.channelName = channelName
    }

    // MARK: - Day filtering

    private enum DayOffset: Int, CaseIterable {
        case yesterday = -1, today = 0, tomorrow = 1

        var label: String {
            switch self {
            case .yesterday: return "Yesterday"
            case .today:     return "Today"
            case .tomorrow:  return "Tomorrow"
            }
        }

        var referenceDate: Date {
            Calendar.current.date(byAdding: .day, value: rawValue, to: Date()) ?? Date()
        }
    }

    private var entries: [EPGEntry] {
        let cal = Calendar.current
        let ref = selectedDay.referenceDate
        return allEntries.filter { cal.isDate($0.start, inSameDayAs: ref) }
    }

    private var hasTomorrow: Bool {
        let cal = Calendar.current
        let tomorrow = DayOffset.tomorrow.referenceDate
        return allEntries.contains { cal.isDate($0.start, inSameDayAs: tomorrow) }
    }

    private var hasYesterday: Bool {
        let cal = Calendar.current
        let yesterday = DayOffset.yesterday.referenceDate
        return allEntries.contains { cal.isDate($0.start, inSameDayAs: yesterday) }
    }

    // MARK: - Geometry helpers

    private func xOffset(for date: Date) -> CGFloat {
        guard let first = entries.first else { return 0 }
        let seconds = date.timeIntervalSince(first.start)
        return CGFloat(seconds / 3600) * Self.pointsPerHour
    }

    private var nowOffset: CGFloat { xOffset(for: Date()) }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Day selector row
            daySelector

            if entries.isEmpty {
                emptyState
            } else {
                timelineContent
            }
        }
        .background(Color.aetherSurface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: channelID) {
            let ids = allEntries.map { $0.id.uuidString }
            let scheduled = await NotificationManager.shared.scheduledEntryIDs(from: ids)
            reminders = Set(allEntries.compactMap { scheduled.contains($0.id.uuidString) ? $0.id : nil })
        }
    }

    // MARK: - Day selector

    private var daySelector: some View {
        HStack(spacing: 0) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)

            Spacer()

            HStack(spacing: 4) {
                ForEach(DayOffset.allCases, id: \.rawValue) { day in
                    let available: Bool = {
                        switch day {
                        case .yesterday: return hasYesterday
                        case .today:     return true
                        case .tomorrow:  return hasTomorrow
                        }
                    }()
                    if available {
                        DayChip(
                            label: day.label,
                            isSelected: selectedDay == day
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedDay = day
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)

            Spacer()
        }
        .padding(.horizontal, 8)
        .background(Color.aetherSurface)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "tv.slash")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
            Text("No EPG data for \(selectedDay.label.lowercased())")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.blockHeight + Self.timelineOffset)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: - Timeline content

    private var timelineContent: some View {
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

                    // "Now" red indicator line (only for today)
                    if selectedDay == .today {
                        nowIndicator
                    }
                }
            }
            .frame(height: Self.blockHeight + Self.timelineOffset + 8)
            .onAppear {
                scrollToNow(proxy: proxy)
            }
            .onChange(of: channelID) { _, _ in
                scrollToNow(proxy: proxy)
            }
            .onChange(of: selectedDay) { _, _ in
                if selectedDay == .today {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollToNow(proxy: proxy)
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(0, anchor: .leading)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                Text(date, style: .time)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
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
                .fill(isNow ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isNow ? Color.accentColor : Color.secondary.opacity(0.25),
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

            // Bell indicator when reminder is set
            if reminders.contains(entry.id) {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "bell.fill")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .padding(4)
                    }
                    Spacer()
                }
            }
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
                EPGProgrammePopover(entry: e, channelName: channelName, reminders: $reminders)
            }
        }
        #endif
    }
}

// MARK: - Day chip

private struct DayChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected
                        ? Color.accentColor
                        : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Programme Detail Popover

private struct EPGProgrammePopover: View {
    let entry: EPGEntry
    let channelName: String
    @Binding var reminders: Set<UUID>

    private var isReminderSet: Bool { reminders.contains(entry.id) }
    private var canRemind: Bool { entry.start.addingTimeInterval(-5 * 60) > Date() }

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

            if canRemind || isReminderSet {
                Divider()

                Button {
                    let entryID = entry.id
                    let entryIDString = entryID.uuidString
                    let currentlySet = isReminderSet
                    Task {
                        if currentlySet {
                            await NotificationManager.shared.cancelReminder(for: entryIDString)
                            reminders.remove(entryID)
                        } else {
                            try? await NotificationManager.shared.scheduleReminder(
                                for: entry, channelName: channelName
                            )
                            reminders.insert(entryID)
                        }
                    }
                } label: {
                    Label(
                        isReminderSet ? "Remove Reminder" : "Remind Me (5 min before)",
                        systemImage: isReminderSet ? "bell.slash" : "bell.badge"
                    )
                    .foregroundStyle(isReminderSet ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(minWidth: 260, maxWidth: 340)
    }
}
