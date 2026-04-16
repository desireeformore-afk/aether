import SwiftUI
import AetherCore

/// Modal sheet for adding a new M3U playlist.
struct AddPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (String, String) -> Void

    @State private var name = ""
    @State private var urlString = ""
    @FocusState private var nameFieldFocused: Bool

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        URL(string: urlString.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        VStack(spacing: 24) {
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

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 12) {
                field(label: "Name", placeholder: "My IPTV", text: $name, focused: true)
                field(label: "M3U URL", placeholder: "https://example.com/playlist.m3u", text: $urlString, focused: false)
            }

            Spacer()

            // Actions
            HStack {
                Spacer()
                Button("Add Playlist") {
                    onAdd(
                        name.trimmingCharacters(in: .whitespaces),
                        urlString.trimmingCharacters(in: .whitespaces)
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
                .tint(Color.aetherPrimary)
            }
        }
        .padding(24)
        .frame(minWidth: 400, idealWidth: 480)
        .background(Color.aetherBackground)
        .onAppear { nameFieldFocused = true }
    }

    @ViewBuilder
    private func field(
        label: String,
        placeholder: String,
        text: Binding<String>,
        focused: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.aetherCaption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.aetherBody)
        }
    }
}
