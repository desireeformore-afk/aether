import Foundation
import AVFoundation

/// Service for managing audio and subtitle tracks.
///
/// Detects available tracks from AVPlayer and manages track selection.
@MainActor
public final class TrackService: ObservableObject {
    @Published public private(set) var audioTracks: [AudioTrack] = []
    @Published public private(set) var subtitleTracks: [SubtitleTrackInfo] = []
    @Published public var selectedAudioTrack: AudioTrack?
    @Published public var selectedSubtitleTrack: SubtitleTrackInfo?
    @Published public var subtitlesEnabled: Bool = false

    private var trackPreferences: [UUID: TrackPreferences] = [:]
    private let userDefaults: UserDefaults
    private let preferencesKey = "aether.track.preferences"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load preferences
        if let data = userDefaults.data(forKey: preferencesKey),
           let decoded = try? JSONDecoder().decode([String: TrackPreferences].self, from: data) {
            self.trackPreferences = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
        }
    }

    // MARK: - Track Detection

    /// Detect available audio and subtitle tracks from AVPlayerItem.
    public func detectTracks(from playerItem: AVPlayerItem) {
        audioTracks = []
        subtitleTracks = []

        guard let asset = playerItem.asset as? AVURLAsset else { return }

        // Detect audio tracks
        if let audioGroup = asset.availableMediaCharacteristicsWithMediaSelectionOptions.first(where: { $0 == .audible }),
           let audioOptions = asset.mediaSelectionGroup(forMediaCharacteristic: audioGroup) {
            audioTracks = audioOptions.options.map { AudioTrack.from($0) }
        }

        // Detect subtitle tracks
        if let subtitleGroup = asset.availableMediaCharacteristicsWithMediaSelectionOptions.first(where: { $0 == .legible }),
           let subtitleOptions = asset.mediaSelectionGroup(forMediaCharacteristic: subtitleGroup) {
            subtitleTracks = subtitleOptions.options.map { SubtitleTrackInfo.from($0) }
        }

        // Auto-select default tracks
        if let defaultAudio = audioTracks.first(where: { $0.isDefault }) {
            selectedAudioTrack = defaultAudio
        } else if let firstAudio = audioTracks.first {
            selectedAudioTrack = firstAudio
        }

        if subtitlesEnabled, let defaultSubtitle = subtitleTracks.first(where: { $0.isDefault }) {
            selectedSubtitleTrack = defaultSubtitle
        }
    }

    // MARK: - Track Selection

    /// Select an audio track.
    public func selectAudioTrack(_ track: AudioTrack, for playerItem: AVPlayerItem) {
        guard let asset = playerItem.asset as? AVURLAsset else { return }

        if let audioGroup = asset.availableMediaCharacteristicsWithMediaSelectionOptions.first(where: { $0 == .audible }),
           let group = asset.mediaSelectionGroup(forMediaCharacteristic: audioGroup),
           let option = group.options.first(where: { $0.displayName == track.id }) {
            playerItem.select(option, in: group)
            selectedAudioTrack = track
        }
    }

    /// Select a subtitle track.
    public func selectSubtitleTrack(_ track: SubtitleTrackInfo?, for playerItem: AVPlayerItem) {
        guard let asset = playerItem.asset as? AVURLAsset else { return }

        if let subtitleGroup = asset.availableMediaCharacteristicsWithMediaSelectionOptions.first(where: { $0 == .legible }),
           let group = asset.mediaSelectionGroup(forMediaCharacteristic: subtitleGroup) {
            if let track = track,
               let option = group.options.first(where: { $0.displayName == track.id }) {
                playerItem.select(option, in: group)
                selectedSubtitleTrack = track
                subtitlesEnabled = true
            } else {
                // Disable subtitles
                playerItem.select(nil, in: group)
                selectedSubtitleTrack = nil
                subtitlesEnabled = false
            }
        }
    }

    /// Toggle subtitles on/off.
    public func toggleSubtitles(for playerItem: AVPlayerItem) {
        if subtitlesEnabled {
            selectSubtitleTrack(nil, for: playerItem)
        } else if let firstSubtitle = subtitleTracks.first {
            selectSubtitleTrack(firstSubtitle, for: playerItem)
        }
    }

    // MARK: - Preferences

    /// Save track preferences for a channel.
    public func savePreferences(for channelId: UUID) {
        let prefs = TrackPreferences(
            preferredAudioLanguage: selectedAudioTrack?.languageCode,
            preferredSubtitleLanguage: selectedSubtitleTrack?.languageCode,
            subtitlesEnabled: subtitlesEnabled
        )

        trackPreferences[channelId] = prefs
        savePreferencesToDisk()
    }

    /// Load and apply track preferences for a channel.
    public func loadPreferences(for channelId: UUID, playerItem: AVPlayerItem) {
        guard let prefs = trackPreferences[channelId] else { return }

        // Apply audio preference
        if let audioLang = prefs.preferredAudioLanguage,
           let track = audioTracks.first(where: { $0.languageCode == audioLang }) {
            selectAudioTrack(track, for: playerItem)
        }

        // Apply subtitle preference
        subtitlesEnabled = prefs.subtitlesEnabled
        if subtitlesEnabled,
           let subtitleLang = prefs.preferredSubtitleLanguage,
           let track = subtitleTracks.first(where: { $0.languageCode == subtitleLang }) {
            selectSubtitleTrack(track, for: playerItem)
        } else if !subtitlesEnabled {
            selectSubtitleTrack(nil, for: playerItem)
        }
    }

    /// Clear preferences for a channel.
    public func clearPreferences(for channelId: UUID) {
        trackPreferences.removeValue(forKey: channelId)
        savePreferencesToDisk()
    }

    private func savePreferencesToDisk() {
        let dict = Dictionary(uniqueKeysWithValues: trackPreferences.map { key, value in
            (key.uuidString, value)
        })

        if let data = try? JSONEncoder().encode(dict) {
            userDefaults.set(data, forKey: preferencesKey)
        }
    }

    // MARK: - External Subtitle Loading

    /// Load external subtitle file (.srt, .vtt).
    public func loadExternalSubtitle(from url: URL) throws {
        guard url.pathExtension == "srt" || url.pathExtension == "vtt" else {
            throw TrackError.unsupportedFormat
        }

        // External subtitle loading would require custom rendering
        // This is a placeholder for the implementation
    }
}

/// Errors related to track operations.
public enum TrackError: Error, LocalizedError {
    case unsupportedFormat
    case loadFailed
    case trackNotFound

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported subtitle format"
        case .loadFailed:
            return "Failed to load track"
        case .trackNotFound:
            return "Track not found"
        }
    }
}
