import SwiftUI
import AetherCore

/// Recording manager view for managing recordings and schedules.
public struct RecordingManagerView: View {
    @ObservedObject var service: RecordingService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: RecordingTab = .active
    @State private var showScheduleSheet = false
    @State private var showDeleteConfirm = false
    @State private var recordingToDelete: UUID?

    public init(service: RecordingService) {
        self.service = service
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recordings")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Schedule") {
                    showScheduleSheet = true
                }
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(RecordingTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            switch selectedTab {
            case .active:
                activeRecordingsView
            case .completed:
                completedRecordingsView
            case .scheduled:
                scheduledRecordingsView
            }
        }
        .frame(width: 700, height: 500)
        .sheet(isPresented: $showScheduleSheet) {
            ScheduleRecordingView(service: service)
        }
        .confirmationDialog(
            "Delete Recording?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = recordingToDelete {
                    try? service.deleteRecording(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the recording file.")
        }
    }

    // MARK: - Active Recordings

    private var activeRecordingsView: some View {
        Group {
            if service.activeRecordings.isEmpty {
                ContentUnavailableView {
                    Label("No Active Recordings", systemImage: "record.circle")
                } description: {
                    Text("Start recording from the player controls")
                }
            } else {
                List {
                    ForEach(Array(service.activeRecordings.values), id: \.id) { recording in
                        ActiveRecordingRow(recording: recording, service: service)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Completed Recordings

    private var completedRecordingsView: some View {
        Group {
            if service.completedRecordings.isEmpty {
                ContentUnavailableView {
                    Label("No Recordings", systemImage: "film")
                } description: {
                    Text("Your completed recordings will appear here")
                }
            } else {
                List {
                    ForEach(service.completedRecordings) { recording in
                        CompletedRecordingRow(
                            recording: recording,
                            onDelete: {
                                recordingToDelete = recording.id
                                showDeleteConfirm = true
                            },
                            onExport: {
                                exportRecording(recording)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Scheduled Recordings

    private var scheduledRecordingsView: some View {
        Group {
            if service.scheduledRecordings.isEmpty {
                ContentUnavailableView {
                    Label("No Scheduled Recordings", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Tap 'Schedule' to set up automatic recordings")
                }
            } else {
                List {
                    ForEach(service.scheduledRecordings) { schedule in
                        ScheduledRecordingRow(
                            schedule: schedule,
                            onCancel: {
                                try? service.cancelSchedule(schedule.id)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Helpers

    private func exportRecording(_ recording: Recording) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(recording.channelName)_\(recording.startTime.timeIntervalSince1970).mp4"
        panel.message = "Export recording"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? service.exportRecording(recording.id, to: url)
        }
    }
}

enum RecordingTab: String, CaseIterable {
    case active = "Active"
    case completed = "Completed"
    case scheduled = "Scheduled"

    var label: String { rawValue }
}

// MARK: - Row Views

struct ActiveRecordingRow: View {
    let recording: Recording
    let service: RecordingService

    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "record.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .symbolEffect(.pulse)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.channelName)
                    .font(.headline)

                if let title = recording.programTitle {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(formatDuration(elapsedTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Stop") {
                Task {
                    try? await service.stopRecording(recording.id)
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.vertical, 4)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                elapsedTime = Date().timeIntervalSince(self.recording.startTime)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct CompletedRecordingRow: View {
    let recording: Recording
    let onDelete: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.fill")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.channelName)
                    .font(.headline)

                if let title = recording.programTitle {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Label(recording.durationFormatted, systemImage: "clock")
                    Label(recording.fileSizeFormatted, systemImage: "internaldrive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(recording.startTime, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Export") {
                onExport()
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

struct ScheduledRecordingRow: View {
    let schedule: RecordingSchedule
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: schedule.isEnabled ? "calendar.badge.clock" : "calendar.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(schedule.isEnabled ? .green : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.channelName)
                    .font(.headline)

                if let title = schedule.programTitle {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(schedule.startTime, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if schedule.isRecurring {
                    Text("Recurring: \(daysOfWeekString(schedule.daysOfWeek))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button("Cancel", role: .destructive) {
                onCancel()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .opacity(schedule.isEnabled ? 1.0 : 0.6)
    }

    private func daysOfWeekString(_ days: Set<Int>) -> String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days.sorted().map { dayNames[$0 - 1] }.joined(separator: ", ")
    }
}

// MARK: - Schedule Recording View

struct ScheduleRecordingView: View {
    @ObservedObject var service: RecordingService
    @Environment(\.dismiss) private var dismiss

    @State private var channelName: String = ""
    @State private var startDate: Date = Date()
    @State private var duration: TimeInterval = 3600
    @State private var programTitle: String = ""
    @State private var isRecurring: Bool = false
    @State private var selectedDays: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Schedule Recording")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Schedule") {
                    scheduleRecording()
                }
                .buttonStyle(.borderedProminent)
                .disabled(channelName.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Form
            Form {
                Section("Channel") {
                    TextField("Channel Name", text: $channelName)
                    TextField("Program Title (Optional)", text: $programTitle)
                }

                Section("Time") {
                    DatePicker("Start Time", selection: $startDate)

                    Picker("Duration", selection: $duration) {
                        Text("30 minutes").tag(1800.0)
                        Text("1 hour").tag(3600.0)
                        Text("2 hours").tag(7200.0)
                        Text("3 hours").tag(10800.0)
                    }
                }

                Section("Repeat") {
                    Toggle("Recurring", isOn: $isRecurring)

                    if isRecurring {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Days of Week")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ForEach(1...7, id: \.self) { day in
                                    DayButton(day: day, isSelected: selectedDays.contains(day)) {
                                        if selectedDays.contains(day) {
                                            selectedDays.remove(day)
                                        } else {
                                            selectedDays.insert(day)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 500, height: 450)
    }

    private func scheduleRecording() {
        let schedule = RecordingSchedule(
            channelId: UUID(), // Would need actual channel selection
            channelName: channelName,
            startTime: startDate,
            duration: duration,
            programTitle: programTitle.isEmpty ? nil : programTitle,
            isRecurring: isRecurring,
            daysOfWeek: selectedDays
        )

        try? service.scheduleRecording(schedule)
        dismiss()
    }
}

struct DayButton: View {
    let day: Int
    let isSelected: Bool
    let action: () -> Void

    private let dayNames = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        Button(action: action) {
            Text(dayNames[day - 1])
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
