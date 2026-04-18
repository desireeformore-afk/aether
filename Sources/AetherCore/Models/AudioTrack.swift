import Foundation
import AVFoundation

/// Audio track information.
public struct AudioTrack: Identifiable, Sendable, Hashable {
    public let id: String
    public var languageCode: String?
    public var languageName: String
    public var label: String?
    public var isDefault: Bool

    public init(
        id: String,
        languageCode: String? = nil,
        languageName: String,
        label: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.languageCode = languageCode
        self.languageName = languageName
        self.label = label
        self.isDefault = isDefault
    }

    /// Create from AVMediaSelectionOption.
    public static func from(_ option: AVMediaSelectionOption) -> AudioTrack {
        let langCode = option.extendedLanguageTag ?? option.locale?.languageCode?.identifier
        let langName = option.displayName
        let label = option.commonMetadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue

        return AudioTrack(
            id: option.displayName,
            languageCode: langCode,
            languageName: langName,
            label: label,
            isDefault: option.isPlayable
        )
    }
}

/// Subtitle track information.
public struct SubtitleTrackInfo: Identifiable, Sendable, Hashable {
    public let id: String
    public var languageCode: String?
    public var languageName: String
    public var label: String?
    public var isDefault: Bool
    public var isForced: Bool
    public var isSDH: Bool

    public init(
        id: String,
        languageCode: String? = nil,
        languageName: String,
        label: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isSDH: Bool = false
    ) {
        self.id = id
        self.languageCode = languageCode
        self.languageName = languageName
        self.label = label
        self.isDefault = isDefault
        self.isForced = isForced
        self.isSDH = isSDH
    }

    /// Create from AVMediaSelectionOption.
    public static func from(_ option: AVMediaSelectionOption) -> SubtitleTrackInfo {
        let langCode = option.extendedLanguageTag ?? option.locale?.languageCode?.identifier
        let langName = option.displayName
        let label = option.commonMetadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue

        return SubtitleTrackInfo(
            id: option.displayName,
            languageCode: langCode,
            languageName: langName,
            label: label,
            isDefault: option.isPlayable,
            isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles),
            isSDH: option.hasMediaCharacteristic(.describesVideoForAccessibility)
        )
    }
}

/// Track preferences per channel.
public struct TrackPreferences: Codable, Sendable {
    public var preferredAudioLanguage: String?
    public var preferredSubtitleLanguage: String?
    public var subtitlesEnabled: Bool

    public init(
        preferredAudioLanguage: String? = nil,
        preferredSubtitleLanguage: String? = nil,
        subtitlesEnabled: Bool = false
    ) {
        self.preferredAudioLanguage = preferredAudioLanguage
        self.preferredSubtitleLanguage = preferredSubtitleLanguage
        self.subtitlesEnabled = subtitlesEnabled
    }
}
