import SwiftUI
import AetherCore

/// Crash reports view for viewing and exporting crash logs.
public struct CrashReportsView: View {
    @Bindable var service: CrashReportingService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReport: CrashReport?
    @State private var showDeleteConfirm = false

    public init(service: CrashReportingService) {
        self.service = service
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Crash Reports")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if !service.crashReports.isEmpty {
                    Button("Delete All") {
                        showDeleteConfirm = true
                    }
                    .buttonStyle(.bordered)
                }

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            if service.crashReports.isEmpty {
                ContentUnavailableView {
                    Label("No Crash Reports", systemImage: "checkmark.circle")
                } description: {
                    Text("Your app is running smoothly!")
                }
            } else {
                List(service.crashReports) { report in
                    CrashReportRow(
                        report: report,
                        onExport: {
                            exportReport(report)
                        },
                        onDelete: {
                            service.deleteCrashReport(report.id)
                        }
                    )
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 700, height: 500)
        .confirmationDialog(
            "Delete All Crash Reports?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                service.deleteAllCrashReports()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all crash reports.")
        }
    }

    private func exportReport(_ report: CrashReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "crash_\(report.timestamp.formatted(date: .numeric, time: .omitted)).txt"
        panel.message = "Export crash report"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? service.exportCrashReport(report, to: url)
        }
    }
}

struct CrashReportRow: View {
    let report: CrashReport
    let onExport: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.errorMessage)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        Label(report.timestamp.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(report.appVersion, systemImage: "app.badge")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(report.osVersion, systemImage: "desktopcomputer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Export Report")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .help("Delete Report")

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Text("Stack Trace:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ScrollView {
                        Text(report.stackTrace)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(height: 150)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    if let desc = report.userDescription {
                        Text("User Description:")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }
}
