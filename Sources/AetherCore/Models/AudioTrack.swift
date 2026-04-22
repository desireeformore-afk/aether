import Foundation
#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

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

    #if canImport(AVFoundation)
    /// Create from AVMediaSelectionOption.
    public static func from(_ option: AVMediaSelectionOption) -> AudioTrack {
        let langCode = option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier
        let langName = option.displayName

        return AudioTrack(
            id: option.displayName,
            languageCode: langCode,
            languageName: langName,
            label: nil,
            isDefault: option.isPlayable
        )
    }
    #endif
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

    #if canImport(AVFoundation)
    /// Create from AVMediaSelectionOption.
    public static func from(_ option: AVMediaSelectionOption) -> SubtitleTrackInfo {
        let langCode = option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier
        let langName = option.displayName

        return SubtitleTrackInfo(
            id: option.displayName,
            languageCode: langCode,
            languageName: langName,
            label: nil,
            isDefault: option.isPlayable,
            isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles),
            isSDH: option.hasMediaCharacteristic(.describesVideoForAccessibility)
        )
    }
    #endif
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
