import SwiftUI
import AetherCore

struct CloudSyncView: View {
    @State private var cloudKit = CloudKitManager.shared
    @State private var showError = false
    
    var body: some View {
        Form {
            Section("iCloud Sync") {
                HStack {
                    Text("Status")
                    Spacer()
                    if cloudKit.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing...")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Ready")
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let lastSync = cloudKit.lastSyncDate {
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        Text(lastSync, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button("Sync Now") {
                    Task {
                        await performSync()
                    }
                }
                .disabled(cloudKit.isSyncing)
            }
            
            Section("What Gets Synced") {
                Label("Playlists", systemImage: "list.bullet")
                Label("Favorites", systemImage: "star.fill")
                Label("Settings", systemImage: "gearshape.fill")
                Label("Watch History", systemImage: "clock.fill")
            }
            
            Section("Privacy") {
                Text("Your data is encrypted and stored in your private iCloud account. Only you can access it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("iCloud Sync")
        .alert("Sync Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            if let error = cloudKit.syncError {
                Text(error.localizedDescription)
            }
        }
    }
    
    private func performSync() async {
        do {
            // Sync favorites
            let favorites = UserDefaults.standard.stringArray(forKey: "favorites") ?? []
            try await cloudKit.syncFavorites(favorites)
            
            // Sync settings
            let settings: [String: Any] = [
                "theme": UserDefaults.standard.string(forKey: "theme") ?? "dark",
                "autoplay": UserDefaults.standard.bool(forKey: "autoplay"),
                "volume": UserDefaults.standard.double(forKey: "volume")
            ]
            try await cloudKit.syncSettings(settings)
        } catch {
            showError = true
        }
    }
}
