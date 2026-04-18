import SwiftUI
import AetherCore
@preconcurrency import AVFoundation

/// Audio and subtitle track picker view.
public struct TrackPickerView: View {
    @ObservedObject var trackService: TrackService
    let playerItem: AVPlayerItem?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: TrackTab = .audio

    public init(trackService: TrackService, playerItem: AVPlayerItem?) {
        self.trackService = trackService
        self.playerItem = playerItem
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Audio & Subtitles")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(TrackTab.allCases, id: \.self) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            switch selectedTab {
            case .audio:
                audioTracksView
            case .subtitles:
                subtitleTracksView
            }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Audio Tracks

    private var audioTracksView: some View {
        Group {
            if trackService.audioTracks.isEmpty {
                ContentUnavailableView {
                    Label("No Audio Tracks", systemImage: "speaker.slash")
                } description: {
                    Text("No alternative audio tracks available")
                }
            } else {
                List(trackService.audioTracks) { track in
                    Button(action: {
                        if let item = playerItem {
                            Task {
                                try? await trackService.selectAudioTrack(track, for: item)
                            }
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.languageName)
                                    .font(.body)

                                if let label = track.label {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if trackService.selectedAudioTrack?.id == track.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }

                            if track.isDefault {
                                Text("DEFAULT")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue, in: Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Subtitle Tracks

    private var subtitleTracksView: some View {
        VStack(spacing: 0) {
            // Subtitle toggle
            HStack {
                Toggle("Enable Subtitles", isOn: Binding(
                    get: { trackService.subtitlesEnabled },
                    set: { enabled in
                        if let item = playerItem {
                            Task {
                                if enabled {
                                    if let firstTrack = trackService.subtitleTracks.first {
                                        try? await trackService.selectSubtitleTrack(firstTrack, for: item)
                                    }
                                } else {
                                    try? await trackService.selectSubtitleTrack(nil, for: item)
                                }
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)

                Spacer()

                Button("Load External…") {
                    loadExternalSubtitle()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if trackService.subtitleTracks.isEmpty {
                ContentUnavailableView {
                    Label("No Subtitle Tracks", systemImage: "captions.bubble.slash")
                } description: {
                    Text("No embedded subtitles available. Load an external file.")
                }
            } else {
                List(trackService.subtitleTracks) { track in
                    Button(action: {
                        if let item = playerItem {
                            Task {
                                try? await trackService.selectSubtitleTrack(track, for: item)
                            }
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(track.languageName)
                                        .font(.body)

                                    if track.isForced {
                                        Text("FORCED")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange, in: Capsule())
                                    }

                                    if track.isSDH {
                                        Text("SDH")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.green, in: Capsule())
                                    }
                                }

                                if let label = track.label {
                                    Text(label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if trackService.selectedSubtitleTrack?.id == track.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }

                            if track.isDefault {
                                Text("DEFAULT")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue, in: Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Helpers

    private func loadExternalSubtitle() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "srt")!,
            .init(filenameExtension: "vtt")!
        ]
        panel.message = "Select a subtitle file"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? trackService.loadExternalSubtitle(from: url)
        }
    }
}

enum TrackTab: String, CaseIterable {
    case audio = "Audio"
    case subtitles = "Subtitles"

    var label: String { rawValue }
}
