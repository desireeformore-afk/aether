import SwiftUI
import AetherCore

struct MemoryMonitorView: View {
    @State var memoryMonitor: MemoryMonitorService
    @State private var showingEvents = false

    var body: some View {
        VStack(spacing: 20) {
            // Current Status
            VStack(spacing: 12) {
                Text("Memory Status")
                    .font(.headline)

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pressure Level")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Circle()
                                .fill(pressureColor)
                                .frame(width: 12, height: 12)
                            Text(memoryMonitor.memoryPressure.description)
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Usage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatBytes(memoryMonitor.currentMemoryUsage))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warnings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(memoryMonitor.memoryWarningCount)")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            // Actions
            HStack(spacing: 12) {
                Button("View Events") {
                    showingEvents = true
                }

                Button("Clear Events") {
                    memoryMonitor.clearMemoryEvents()
                }
                .disabled(memoryMonitor.getMemoryEvents().isEmpty)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingEvents) {
            MemoryEventsView(memoryMonitor: memoryMonitor)
        }
    }

    private var pressureColor: Color {
        switch memoryMonitor.memoryPressure {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct MemoryEventsView: View {
    @State var memoryMonitor: MemoryMonitorService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Memory Events")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Events List
            if memoryMonitor.getMemoryEvents().isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No memory events recorded")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(memoryMonitor.getMemoryEvents().reversed(), id: \.timestamp) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle()
                                    .fill(levelColor(event.level))
                                    .frame(width: 8, height: 8)
                                Text(event.level.description)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(event.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text(event.action)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(formatBytes(event.memoryUsage))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    private func levelColor(_ level: MemoryMonitorService.MemoryPressureLevel) -> Color {
        switch level {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
