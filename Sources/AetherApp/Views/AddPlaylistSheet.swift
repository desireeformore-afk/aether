import SwiftUI
import AetherCore

/// Modal sheet for adding a new playlist (M3U or Xtream Codes).
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
    // Xtream Codes fields
    @State private var xtreamHost = ""
    @State private var xtreamUser = ""
    @State private var xtreamPass = ""
    @State private var xtreamEPGURL = ""

    @FocusState private var isNameFocused: Bool

    private var isValid: Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return false }
        switch mode {
        case .m3u:
            return URL(string: urlString.trimmingCharacters(in: .whitespaces)) != nil
        case .xtream:
            return !xtreamHost.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !xtreamUser.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !xtreamPass.isEmpty
        }
    }

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
                        Text("M3U URL").tag(PlaylistType.m3u)
                        Text("Xtream Codes").tag(PlaylistType.xtream)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)

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
    }

    // MARK: - Mode forms

    @ViewBuilder
    private var m3uFields: some View {
        formField(
            label: "M3U URL",
            placeholder: "https://example.com/playlist.m3u",
            text: $urlString
        )
        formField(
            label: "EPG (XMLTV) URL",
            placeholder: "https://example.com/epg.xml  (optional)",
            text: $epgURLString,
            required: false
        )
    }

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
        // Info
        Label(
            "Channels will be fetched via the panel's M3U+ endpoint.",
            systemImage: "info.circle"
        )
        .font(.aetherCaption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private func addPlaylist() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let record: PlaylistRecord

        switch mode {
        case .m3u:
            record = PlaylistRecord(
                name: n,
                urlString: urlString.trimmingCharacters(in: .whitespaces),
                playlistType: .m3u,
                epgURLString: epgURLString.trimmingCharacters(in: .whitespaces).nilIfEmpty
            )
        case .xtream:
            record = PlaylistRecord(
                name: n,
                playlistType: .xtream,
                xstreamHost: xtreamHost.trimmingCharacters(in: .whitespaces),
                xstreamUsername: xtreamUser.trimmingCharacters(in: .whitespaces),
                xstreamPassword: xtreamPass,
                epgURLString: xtreamEPGURL.trimmingCharacters(in: .whitespaces).nilIfEmpty
            )
        }

        modelContext.insert(record)
        onAdded(record)
        dismiss()
    }

    // MARK: - Helpers

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
                        .foregroundStyle(Color.aetherSecondary.opacity(0.7))
                }
            }
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.aetherBody)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
