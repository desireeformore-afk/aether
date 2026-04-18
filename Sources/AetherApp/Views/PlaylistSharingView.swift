import SwiftUI
import AetherCore

struct PlaylistSharingView: View {
    @State private var sharingService = PlaylistSharingService()
    @State private var selectedPlaylist: Playlist?
    @State private var showShareSheet = false
    @State private var showImportSheet = false
    @State private var shareCode = ""
    @State private var isPublic = false
    @State private var expirationDays = 30
    @State private var shareDescription = ""
    @State private var shareTags = ""
    @State private var generatedShare: ShareablePlaylist?
    @State private var qrCodeImage: CGImage?
    @State private var showPublicDirectory = false
    @State private var searchQuery = ""

    var body: some View {
        NavigationStack {
            List {
                Section("My Shared Playlists") {
                    if sharingService.sharedPlaylists.isEmpty {
                        Text("No shared playlists yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sharingService.sharedPlaylists) { shareable in
                            SharedPlaylistRow(
                                shareable: shareable,
                                stats: sharingService.getStats(for: shareable.shareCode),
                                onDelete: {
                                    sharingService.deleteShare(shareable)
                                },
                                onShowQR: {
                                    generatedShare = shareable
                                    generateQRCode(for: shareable)
                                }
                            )
                        }
                    }
                }

                Section("Actions") {
                    Button(action: { showShareSheet = true }) {
                        Label("Share a Playlist", systemImage: "square.and.arrow.up")
                    }

                    Button(action: { showImportSheet = true }) {
                        Label("Import from Share Code", systemImage: "square.and.arrow.down")
                    }

                    Button(action: { showPublicDirectory = true }) {
                        Label("Browse Public Playlists", systemImage: "globe")
                    }
                }
            }
            .navigationTitle("Playlist Sharing")
            .sheet(isPresented: $showShareSheet) {
                SharePlaylistSheet(
                    sharingService: sharingService,
                    onShare: { share in
                        generatedShare = share
                        generateQRCode(for: share)
                    }
                )
            }
            .sheet(isPresented: $showImportSheet) {
                ImportPlaylistSheet(sharingService: sharingService)
            }
            .sheet(isPresented: $showPublicDirectory) {
                PublicPlaylistDirectoryView(sharingService: sharingService)
            }
            .sheet(item: $generatedShare) { share in
                ShareDetailsView(
                    shareable: share,
                    qrCodeImage: qrCodeImage,
                    onDismiss: { generatedShare = nil }
                )
            }
        }
    }

    private func generateQRCode(for shareable: ShareablePlaylist) {
        qrCodeImage = sharingService.generateQRCode(for: shareable)
    }
}

struct SharedPlaylistRow: View {
    let shareable: ShareablePlaylist
    let stats: PlaylistShareStats?
    let onDelete: () -> Void
    let onShowQR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(shareable.name)
                        .font(.headline)

                    Text(shareable.shareCode)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if shareable.isPublic {
                    Image(systemName: "globe")
                        .foregroundStyle(.blue)
                }

                if shareable.isExpired {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.red)
                }
            }

            if let stats = stats {
                HStack(spacing: 12) {
                    Label("\(stats.viewCount)", systemImage: "eye")
                    Label("\(stats.importCount)", systemImage: "square.and.arrow.down")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button(action: onShowQR) {
                    Label("QR Code", systemImage: "qrcode")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: copyShareLink) {
                    Label("Copy Link", systemImage: "link")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func copyShareLink() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareable.webShareURL.absoluteString, forType: .string)
        #endif
    }
}

struct SharePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var sharingService: PlaylistSharingService
    let onShare: (ShareablePlaylist) -> Void

    @State private var selectedPlaylist: Playlist?
    @State private var isPublic = false
    @State private var expirationDays = 30
    @State private var neverExpires = false
    @State private var description = ""
    @State private var tags = ""

    // Mock playlists for demo
    @State private var availablePlaylists: [Playlist] = [
        Playlist(name: "Sports Channels", url: URL(string: "http://example.com/sports.m3u")!, type: .m3u),
        Playlist(name: "News Networks", url: URL(string: "http://example.com/news.m3u")!, type: .m3u),
        Playlist(name: "Entertainment", url: URL(string: "http://example.com/entertainment.m3u")!, type: .m3u)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Select Playlist") {
                    Picker("Playlist", selection: $selectedPlaylist) {
                        Text("Choose...").tag(nil as Playlist?)
                        ForEach(availablePlaylists, id: \.id) { playlist in
                            Text(playlist.name).tag(playlist as Playlist?)
                        }
                    }
                }

                Section("Share Settings") {
                    Toggle("Make Public", isOn: $isPublic)
                        .help("Public playlists appear in the directory")

                    Toggle("Never Expires", isOn: $neverExpires)

                    if !neverExpires {
                        Stepper("Expires in \(expirationDays) days", value: $expirationDays, in: 1...365)
                    }
                }

                Section("Optional Details") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)

                    TextField("Tags (comma-separated)", text: $tags)
                        .help("e.g., sports, hd, free")
                }
            }
            .navigationTitle("Share Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        createShare()
                    }
                    .disabled(selectedPlaylist == nil)
                }
            }
        }
    }

    private func createShare() {
        guard let playlist = selectedPlaylist else { return }

        let expiresIn: TimeInterval? = neverExpires ? nil : TimeInterval(expirationDays * 86400)
        let tagArray = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let share = sharingService.createShareLink(
            for: playlist,
            channelCount: 150, // Mock count
            isPublic: isPublic,
            expiresIn: expiresIn,
            description: description.isEmpty ? nil : description,
            tags: tagArray
        )

        onShare(share)
        dismiss()
    }
}

struct ImportPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var sharingService: PlaylistSharingService

    @State private var shareCode = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importedPlaylist: Playlist?

    var body: some View {
        NavigationStack {
            Form {
                Section("Import") {
                    TextField("Share Code", text: $shareCode)
                        .textCase(.uppercase)
                        .font(.system(.body, design: .monospaced))
                        .help("Enter the 8-character share code")

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    if let playlist = importedPlaylist {
                        Text("✓ Successfully imported: \(playlist.name)")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Enter Share Code")
                } footer: {
                    Text("Share codes are 8 characters long (e.g., ABCD1234)")
                }
            }
            .navigationTitle("Import Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task { await importPlaylist() }
                    }
                    .disabled(shareCode.count != 8 || isImporting)
                }
            }
        }
    }

    private func importPlaylist() async {
        isImporting = true
        errorMessage = nil

        do {
            let playlist = try await sharingService.importFromShareCode(shareCode)
            importedPlaylist = playlist

            try await Task.sleep(for: .seconds(1.5))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }
}

struct ShareDetailsView: View {
    let shareable: ShareablePlaylist
    let qrCodeImage: CGImage?
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(shareable.name)
                    .font(.title)
                    .bold()

                if let qrImage = qrCodeImage {
                    Image(decorative: qrImage, scale: 1.0)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 300, height: 300)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                }

                VStack(spacing: 8) {
                    Text("Share Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(shareable.shareCode)
                        .font(.system(.title2, design: .monospaced))
                        .bold()
                }

                VStack(spacing: 8) {
                    Text("Share Link")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(shareable.webShareURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 12) {
                    Button(action: copyLink) {
                        Label("Copy Link", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: saveQRCode) {
                        Label("Save QR", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Share Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    private func copyLink() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareable.webShareURL.absoluteString, forType: .string)
        #endif
    }

    private func saveQRCode() {
        // Implementation for saving QR code to file
    }
}

struct PublicPlaylistDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var sharingService: PlaylistSharingService
    @State private var searchQuery = ""

    var filteredPlaylists: [ShareablePlaylist] {
        if searchQuery.isEmpty {
            return sharingService.getPublicPlaylists()
        } else {
            return sharingService.searchPublicPlaylists(query: searchQuery)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredPlaylists) { playlist in
                    PublicPlaylistRow(playlist: playlist, sharingService: sharingService)
                }
            }
            .searchable(text: $searchQuery, prompt: "Search playlists")
            .navigationTitle("Public Playlists")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct PublicPlaylistRow: View {
    let playlist: ShareablePlaylist
    @Bindable var sharingService: PlaylistSharingService
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(playlist.name)
                .font(.headline)

            if let description = playlist.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("\(playlist.channelCount) channels", systemImage: "tv")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let stats = sharingService.getStats(for: playlist.shareCode) {
                    Label("\(stats.importCount) imports", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !playlist.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(playlist.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                }
            }

            Button(action: { Task { await importPlaylist() } }) {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isImporting)
        }
        .padding(.vertical, 4)
    }

    private func importPlaylist() async {
        isImporting = true
        do {
            _ = try await sharingService.importFromShareCode(playlist.shareCode)
        } catch {
            print("Import failed: \(error)")
        }
        isImporting = false
    }
}
