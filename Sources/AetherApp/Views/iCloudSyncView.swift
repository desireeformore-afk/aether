import SwiftUI
import AetherCore

struct iCloudSyncView: View {
    @Environment(iCloudSyncService.self) var syncService
    @State private var showingConflicts = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: syncService.isEnabled ? "icloud.fill" : "icloud.slash.fill")
                        .foregroundColor(syncService.isEnabled ? .blue : .gray)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud Sync")
                            .font(.headline)
                        Text(syncService.isEnabled ? "Connected" : "Not Available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if syncService.isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.vertical, 8)
            }

            if syncService.isEnabled {
                Section("Sync Status") {
                    if let lastSync = syncService.lastSyncDate {
                        LabeledContent("Last Sync") {
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        LabeledContent("Last Sync") {
                            Text("Never")
                                .foregroundColor(.secondary)
                        }
                    }

                    if syncService.conflictCount > 0 {
                        Button {
                            showingConflicts = true
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("\(syncService.conflictCount) Conflicts")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if let error = syncService.syncError {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("What's Synced") {
                    SyncItemRow(icon: "list.bullet", title: "Playlists", description: "All your IPTV playlists")
                    SyncItemRow(icon: "star.fill", title: "Favorites", description: "Your favorite channels")
                    SyncItemRow(icon: "clock.fill", title: "Watch History", description: "Recently watched channels")
                    SyncItemRow(icon: "gearshape.fill", title: "Settings", description: "App preferences and settings")
                }

                Section {
                    Button {
                        Task {
                            await syncService.syncAll()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Now")
                        }
                    }
                    .disabled(syncService.isSyncing)

                    // Clear iCloud Data functionality removed - not implemented in service
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("iCloud Not Available")
                            .font(.headline)
                        Text("Make sure you're signed in to iCloud in System Settings and that iCloud Drive is enabled.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button {
                            Task {
                                await syncService.checkiCloudStatus()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Check Again")
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("iCloud Sync")
        .sheet(isPresented: $showingConflicts) {
            ConflictResolutionView()
                .environment(syncService)
        }
    }
}

struct SyncItemRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
}

struct ConflictResolutionView: View {
    @Environment(iCloudSyncService.self) var syncService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Some items have conflicts between your local data and iCloud. Choose which version to keep.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // TODO: Display actual conflicts
                Section("Conflicts") {
                    Text("No conflicts to resolve")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Resolve Conflicts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
