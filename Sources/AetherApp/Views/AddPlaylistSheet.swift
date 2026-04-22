import SwiftUI
import UniformTypeIdentifiers
import AetherCore

/// Modal sheet for adding a new playlist (M3U or Xtream Codes).
/// Supports: URL entry, local file picker, and drag & drop of .m3u/.m3u8 files.
struct AddPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Called after a playlist has been inserted into the model context.
    let onAdded: (PlaylistRecord) -> Void

    @State private var mode: PlaylistType = .m3u
    @State private var name = ""
    // M3U fields
    @State private var urlString = ""
    @State private var epgURLString = ""
    @State private var localFileURL: URL? = nil
    @State private var isDropTargeted = false
    @State private var showFilePicker = false
    // Xtream Codes fields
    @State private var xtreamHost = ""
    @State private var xtreamUser = ""
    @State private var xtreamPass = ""
    @State private var xtreamEPGURL = ""

    @FocusState private var isNameFocused: Bool

    // MARK: - Validation

    private var isValid: Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return false }
        switch mode {
        case .m3u:
            // Valid if either a local file OR a valid URL is provided
            if localFileURL != nil { return true }
            return URL(string: urlString.trimmingCharacters(in: .whitespaces)) != nil
        case .xtream:
            return !xtreamHost.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !xtreamUser.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !xtreamPass.isEmpty
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(Color.aetherPrimary)
                Text("Add Playlist")
                    .font(.aetherTitle)
                    .foregroundStyle(Color.aetherText)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Mode picker
                    Picker("Source", selection: $mode) {
                        Text("M3U URL / File").tag(PlaylistType.m3u)
                        Text("Xtream Codes").tag(PlaylistType.xtream)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                    .onChange(of: mode) { _, _ in
                        // Reset file state when switching modes
                        localFileURL = nil
                        urlString = ""
                    }

                    // Common: name
                    formField(label: "Playlist Name", placeholder: "My IPTV", text: $name)
                        .focused($isNameFocused)

                    Divider()

                    // Mode-specific fields
                    switch mode {
                    case .m3u:
                        m3uFields
                    case .xtream:
                        xtreamFields
                    }
                }
                .padding(24)
            }

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Add Playlist", action: addPlaylist)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.aetherPrimary)
            }
            .padding(24)
        }
        .frame(minWidth: 440, idealWidth: 500)
        .background(Color.aetherBackground)
        .onAppear { isNameFocused = true }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.m3uPlaylist, .m3u8Playlist, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImporterResult(result)
        }
    }

    // MARK: - M3U Fields

    @ViewBuilder
    private var m3uFields: some View {
        // Drag & drop zone (shown above URL field)
        dropZone

        // Divider with "or" label
        HStack {
            Rectangle().fill(Color.aetherText.opacity(0.15)).frame(height: 1)
            Text("or enter URL")
                .font(.system(size: 11))
                .foregroundStyle(Color.aetherText.opacity(0.4))
            Rectangle().fill(Color.aetherText.opacity(0.15)).frame(height: 1)
        }

        formField(
            label: "M3U URL",
            placeholder: "https://example.com/playlist.m3u",
            text: $urlString
        )
        .disabled(localFileURL != nil)
        .opacity(localFileURL != nil ? 0.4 : 1)

        formField(
            label: "EPG (XMLTV) URL",
            placeholder: "https://example.com/epg.xml  (optional)",
            text: $epgURLString,
            required: false
        )
    }

    // MARK: - Drop Zone

    @ViewBuilder
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTargeted ? Color.aetherAccent : Color.aetherText.opacity(0.2),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDropTargeted
                              ? Color.aetherAccent.opacity(0.08)
                              : Color.aetherSurface.opacity(0.5))
                )
                .frame(height: 90)

            if let fileURL = localFileURL {
                // File selected — show name + clear button
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundStyle(Color.aetherAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileURL.lastPathComponent)
                            .font(.aetherBody)
                            .foregroundStyle(Color.aetherText)
                            .lineLimit(1)
                        Text("Local file")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        localFileURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                        .font(.title2)
                        .foregroundStyle(isDropTargeted ? Color.aetherAccent : Color.aetherText.opacity(0.4))
                    Text(isDropTargeted ? "Drop to add" : "Drop .m3u / .m3u8 here")
                        .font(.aetherCaption)
                        .foregroundStyle(isDropTargeted ? Color.aetherAccent : Color.aetherText.opacity(0.5))
                    Button("Choose File…") { showFilePicker = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.aetherPrimary)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .animation(.easeInOut(duration: 0.15), value: localFileURL)
    }

    // MARK: - Xtream Fields

    @ViewBuilder
    private var xtreamFields: some View {
        formField(
            label: "Panel URL",
            placeholder: "http://host:port",
            text: $xtreamHost
        )
        formField(
            label: "Username",
            placeholder: "your_username",
            text: $xtreamUser
        )
        VStack(alignment: .leading, spacing: 4) {
            Text("Password")
                .font(.aetherCaption)
                .foregroundStyle(.secondary)
            SecureField("your_password", text: $xtreamPass)
                .textFieldStyle(.roundedBorder)
                .font(.aetherBody)
        }
        formField(
            label: "EPG (XMLTV) URL Override",
            placeholder: "Leave empty to use panel's built-in EPG",
            text: $xtreamEPGURL,
            required: false
        )
        Label(
            "Channels will be fetched via the panel's M3U+ endpoint.",
            systemImage: "info.circle"
        )
        .font(.aetherCaption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Drag & Drop Handler

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            guard ext == "m3u" || ext == "m3u8" else { return }
            DispatchQueue.main.async {
                self.localFileURL = url
                // Auto-fill name from filename if empty
                if self.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.name = url.deletingPathExtension().lastPathComponent
                }
            }
        }
        return true
    }

    // MARK: - File Importer Handler

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Start security-scoped access so the app can read the file later
            _ = url.startAccessingSecurityScopedResource()
            localFileURL = url
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        case .failure:
            break
        }
    }

    // MARK: - Add Action

    private func addPlaylist() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let record: PlaylistRecord

        switch mode {
        case .m3u:
            // Prefer local file URL; fall back to typed URL string
            let finalURL: String
            if let fileURL = localFileURL {
                finalURL = fileURL.absoluteString
            } else {
                finalURL = urlString.trimmingCharacters(in: .whitespaces)
            }
            record = PlaylistRecord(
                name: n,
                urlString: finalURL,
                playlistType: .m3u,
                epgURLString: epgURLString.trimmingCharacters(in: .whitespaces).nilIfEmpty
            )
        case .xtream:
            record = PlaylistRecord(
                name: n,
                playlistType: .xtream,
                xstreamHost: xtreamHost.trimmingCharacters(in: .whitespaces),
                xstreamUsername: xtreamUser.trimmingCharacters(in: .whitespaces),
                xstreamPassword: nil,
                epgURLString: xtreamEPGURL.trimmingCharacters(in: .whitespaces).nilIfEmpty
            )
        }

        modelContext.insert(record)
        try? modelContext.save()

        if mode == .xtream {
            try? KeychainService.save(password: xtreamPass, for: record.id.uuidString)
        }

        onAdded(record)
        dismiss()
    }

    // MARK: - Form Field Helper

    @ViewBuilder
    private func formField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        required: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.aetherCaption)
                    .foregroundStyle(.secondary)
                if !required {
                    Text("(optional)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.aetherText.opacity(0.4))
                }
            }
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.aetherBody)
        }
    }
}

// MARK: - UTType extensions for M3U

private extension UTType {
    static let m3uPlaylist  = UTType(filenameExtension: "m3u")  ?? .plainText
    static let m3u8Playlist = UTType(filenameExtension: "m3u8") ?? .plainText
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
