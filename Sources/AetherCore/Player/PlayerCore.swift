import Foundation
import Observation
import VLCKit
@preconcurrency import MediaPlayer
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - PlayerState

/// Playback state of ``PlayerCore``.
public enum PlayerState: Sendable, Equatable {
    /// No channel is loaded.
    case idle
    /// Channel is loading / buffering.
    case loading
    /// Channel is playing.
    case playing
    /// Playback is paused.
    case paused
    /// Playback failed with an error message.
    case error(String)
}

// MARK: - PlayerPlaybackConfig

enum PlayerPlaybackConfig {
    enum CachingProfile: Equatable {
        case standard
        case interactiveSeek
        case strengthened

        var logLabel: String {
            switch self {
            case .standard: return "standard"
            case .interactiveSeek: return "interactive-seek"
            case .strengthened: return "strengthened"
            }
        }
    }

    enum PlaybackContainer: Equatable {
        case hls
        case matroska
        case mp4
        case quickTime
        case avi
        case transportStream
        case other

        var logLabel: String {
            switch self {
            case .hls: return "HLS"
            case .matroska: return "Matroska"
            case .mp4: return "MP4"
            case .quickTime: return "QuickTime"
            case .avi: return "AVI"
            case .transportStream: return "MPEG-TS"
            case .other: return "Other"
            }
        }
    }

    enum SeekStrategy: Equatable {
        case none
        case directTime
        case directPosition
        case resilientMatroska

        var logLabel: String {
            switch self {
            case .none: return "none"
            case .directTime: return "direct-time"
            case .directPosition: return "direct-position"
            case .resilientMatroska: return "resilient-matroska"
            }
        }
    }

    enum PlaybackRoute: Equatable {
        case nativeDirect
        case redirectCached
        case localHLSProxy
        case limitedSeek

        var logLabel: String {
            switch self {
            case .nativeDirect: return "native-direct"
            case .redirectCached: return "redirect-cached"
            case .localHLSProxy: return "local-hls-proxy"
            case .limitedSeek: return "limited-seek"
            }
        }
    }

    struct PlaybackPlan: Equatable {
        let isLiveStream: Bool
        let container: PlaybackContainer
        let seekStrategy: SeekStrategy
        let route: PlaybackRoute
        let cachingProfile: CachingProfile
        let startPosition: Double?

        var canSeek: Bool {
            seekStrategy != .none
        }

        var usesFastSeek: Bool {
            switch seekStrategy {
            case .directTime, .directPosition, .resilientMatroska: return true
            case .none: return false
            }
        }

        var usesMatroskaSeekPercent: Bool {
            seekStrategy == .resilientMatroska
        }

        var usesStartTime: Bool {
            guard canSeek, let startPosition else { return false }
            return startPosition > 0 && startPosition.isFinite
        }

        var passesStartTimeToVLC: Bool {
            usesStartTime && route != .localHLSProxy
        }

        var prefersPositionSeek: Bool {
            switch seekStrategy {
            case .directPosition, .resilientMatroska: return true
            case .directTime, .none: return false
            }
        }

        var usesPostSeekWatchdog: Bool {
            seekStrategy == .resilientMatroska
        }

        var restartsPlaybackForSeek: Bool {
            route == .localHLSProxy
        }

        var limitationMessage: String? {
            switch route {
            case .limitedSeek:
                return "This MKV provider has limited seeking. A different language/quality variant may seek faster."
            case .localHLSProxy:
                return "Optimized MKV seeking is active."
            case .nativeDirect, .redirectCached:
                return nil
            }
        }
    }

    static let liveNetworkCachingMilliseconds = 1500
    static let liveFileCachingMilliseconds = 1000
    static let liveLiveCachingMilliseconds = 1500
    static let vodNetworkCachingMilliseconds = 2500
    static let vodFileCachingMilliseconds = 2500
    static let seekNetworkCachingMilliseconds = 700
    static let seekFileCachingMilliseconds = 700
    static let seekLiveCachingMilliseconds = 700
    static let strengthenedLiveNetworkCachingMilliseconds = 2500
    static let strengthenedLiveFileCachingMilliseconds = 1500
    static let strengthenedLiveLiveCachingMilliseconds = 2500
    static let strengthenedVODNetworkCachingMilliseconds = 12000
    static let strengthenedVODFileCachingMilliseconds = 12000
    static let startupPlaybackTimeoutSeconds = 20.0
    static let seekStartupPlaybackTimeoutSeconds = 12.0
    static let strengthenedStartupPlaybackTimeoutSeconds = 35.0
    static let startupWatchdogMaxRetries = 1
    static let startupWatchdogPollIntervalSeconds = 0.5
    static let startupWatchdogLogIntervalSeconds = 5.0
    static let startupProgressMinimumTimeAdvanceMilliseconds: Int32 = 250
    static let startupProgressMinimumPositionAdvance: Float = 0.0001
    static let postSeekWatchdogTimeoutSeconds = 2.5
    static let postSeekWatchdogPollIntervalSeconds = 0.4
    static let postSeekTargetToleranceSeconds = 6.0
    static let postSeekMaxRecoveries = 0
    static let vodSeekDebounceMilliseconds = 120
    static let matroskaSeekDebounceMilliseconds = 220
    static let matroskaPositionAssistDelayMilliseconds = 350
    static let redirectProbeTimeoutSeconds: TimeInterval = 1.6
    static let httpUserAgent = "VLC/3.0.20 LibVLC/3.0.20"
    static let libraryOptions = [
        "--quiet",
        "--verbose=0",
        "--log-verbose=0",
        "--vout=samplebufferdisplay",
        "--no-video-title-show",
        "--no-spu",
        "--sub-track=-1",
        "--no-sub-autodetect-file",
        "--no-stats",
        "--avcodec-options=loglevel=quiet"
    ]
    private static let vodExtensions: Set<String> = ["mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v"]

    static func networkCachingMilliseconds(isLiveStream: Bool, cachingProfile: CachingProfile = .standard) -> Int {
        switch (isLiveStream, cachingProfile) {
        case (true, .standard): return liveNetworkCachingMilliseconds
        case (true, .interactiveSeek): return seekNetworkCachingMilliseconds
        case (true, .strengthened): return strengthenedLiveNetworkCachingMilliseconds
        case (false, .standard): return vodNetworkCachingMilliseconds
        case (false, .interactiveSeek): return seekNetworkCachingMilliseconds
        case (false, .strengthened): return strengthenedVODNetworkCachingMilliseconds
        }
    }

    static func fileCachingMilliseconds(isLiveStream: Bool, cachingProfile: CachingProfile = .standard) -> Int {
        switch (isLiveStream, cachingProfile) {
        case (true, .standard): return liveFileCachingMilliseconds
        case (true, .interactiveSeek): return seekFileCachingMilliseconds
        case (true, .strengthened): return strengthenedLiveFileCachingMilliseconds
        case (false, .standard): return vodFileCachingMilliseconds
        case (false, .interactiveSeek): return seekFileCachingMilliseconds
        case (false, .strengthened): return strengthenedVODFileCachingMilliseconds
        }
    }

    static func liveCachingMilliseconds(isLiveStream: Bool, cachingProfile: CachingProfile = .standard) -> Int {
        switch (isLiveStream, cachingProfile) {
        case (true, .standard): return liveLiveCachingMilliseconds
        case (true, .interactiveSeek): return seekLiveCachingMilliseconds
        case (true, .strengthened): return strengthenedLiveLiveCachingMilliseconds
        case (false, .standard): return vodNetworkCachingMilliseconds
        case (false, .interactiveSeek): return seekLiveCachingMilliseconds
        case (false, .strengthened): return strengthenedVODNetworkCachingMilliseconds
        }
    }

    static func startupTimeoutSeconds(cachingProfile: CachingProfile) -> Double {
        switch cachingProfile {
        case .standard:
            return startupPlaybackTimeoutSeconds
        case .interactiveSeek:
            return seekStartupPlaybackTimeoutSeconds
        case .strengthened:
            return strengthenedStartupPlaybackTimeoutSeconds
        }
    }

    static func isLiveStream(channel: Channel) -> Bool {
        playbackPlan(for: channel).isLiveStream
    }

    static func playbackPlan(
        for channel: Channel,
        cachingProfile: CachingProfile = .standard,
        startPosition: Double? = nil,
        localHLSProxyAvailable: Bool = false
    ) -> PlaybackPlan {
        let container = playbackContainer(for: channel.streamURL)
        let live = isLiveContent(channel: channel)
        let hasStartPosition = startPosition.map { $0.isFinite && $0 > 0 } == true
        let strategy: SeekStrategy
        let route: PlaybackRoute

        if live {
            strategy = .none
            route = .nativeDirect
        } else {
            switch container {
            case .matroska:
                if hasStartPosition, localHLSProxyAvailable {
                    strategy = .directTime
                    route = .localHLSProxy
                } else {
                    strategy = .resilientMatroska
                    route = hasStartPosition ? .limitedSeek : .redirectCached
                }
            case .mp4, .quickTime, .avi:
                strategy = .directPosition
                route = .nativeDirect
            case .hls, .transportStream, .other:
                strategy = .directTime
                route = .nativeDirect
            }
        }

        let normalizedStart: Double?
        if live {
            normalizedStart = nil
        } else if let startPosition, startPosition.isFinite, startPosition > 0 {
            normalizedStart = startPosition
        } else {
            normalizedStart = nil
        }

        return PlaybackPlan(
            isLiveStream: live,
            container: container,
            seekStrategy: strategy,
            route: route,
            cachingProfile: cachingProfile,
            startPosition: normalizedStart
        )
    }

    static func cachingProfile(
        for channel: Channel,
        startPosition: Double?,
        startupRetryCount: Int
    ) -> CachingProfile {
        if startupRetryCount > 0 {
            return .strengthened
        }

        let container = playbackContainer(for: channel.streamURL)
        let shouldUseSeekProfile = startPosition.map { $0.isFinite && $0 > 0 } == true
            && container == .matroska
            && !isLiveContent(channel: channel)

        return shouldUseSeekProfile ? .interactiveSeek : .standard
    }

    static func playbackContainer(for url: URL) -> PlaybackContainer {
        switch url.pathExtension.lowercased() {
        case "m3u", "m3u8":
            return .hls
        case "mkv", "mk3d", "webm":
            return .matroska
        case "mp4", "m4v":
            return .mp4
        case "mov", "qt":
            return .quickTime
        case "avi":
            return .avi
        case "ts", "m2ts", "mts":
            return .transportStream
        default:
            return .other
        }
    }

    private static func isLiveContent(channel: Channel) -> Bool {
        switch channel.contentType {
        case .liveTV:
            let ext = channel.streamURL.pathExtension.lowercased()
            return !vodExtensions.contains(ext)
        case .movie, .series:
            return false
        }
    }

    static func mediaOptions(
        isLiveStream: Bool,
        cachingProfile: CachingProfile,
        startPosition: Double? = nil
    ) -> [String] {
        let fallbackPlan = PlaybackPlan(
            isLiveStream: isLiveStream,
            container: .other,
            seekStrategy: isLiveStream ? .none : .directTime,
            route: .nativeDirect,
            cachingProfile: cachingProfile,
            startPosition: startPosition
        )
        return mediaOptions(plan: fallbackPlan)
    }

    static func mediaOptions(plan: PlaybackPlan) -> [String] {
        var options = [
            ":network-caching=\(networkCachingMilliseconds(isLiveStream: plan.isLiveStream, cachingProfile: plan.cachingProfile))",
            ":file-caching=\(fileCachingMilliseconds(isLiveStream: plan.isLiveStream, cachingProfile: plan.cachingProfile))",
            ":live-caching=\(liveCachingMilliseconds(isLiveStream: plan.isLiveStream, cachingProfile: plan.cachingProfile))",
            ":http-reconnect",
            ":http-continuous",
            ":rtsp-tcp",
            ":sub-track=-1",
            ":no-sub-autodetect-file",
            ":no-spu",
            ":http-user-agent=\(httpUserAgent)"
        ]

        if plan.usesFastSeek {
            options.append(":input-fast-seek")
        }

        if plan.usesMatroskaSeekPercent {
            options.append(":mkv-seek-percent")
        }

        if plan.passesStartTimeToVLC {
            if let startPosition = plan.startPosition {
                options.append(":start-time=\(vlcSeconds(startPosition))")
            }
        }

        return options
    }

    private static func vlcSeconds(_ seconds: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(0, seconds))
    }
}

private extension PlayerState {
    var logDescription: String {
        switch self {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .error(let message):
            return "error(\(message))"
        }
    }
}

// MARK: - VLCTrack

/// Lightweight descriptor for an audio or subtitle track reported by VLC.
public struct VLCTrack: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let displayName: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
        // Strip "[Track N]" noise that VLC sometimes prepends
        let clean = name.replacingOccurrences(of: #"\[Track \d+\] "#, with: "", options: .regularExpression)
        self.displayName = clean.isEmpty ? "Track \(id)" : clean
    }
}

// MARK: - PlayerCore

/// `@MainActor` wrapper around `VLCMediaPlayer` for IPTV stream playback.
///
/// Dropped: AVPlayer, LocalHLSProxy, HTTPBypassProtocol, ffprobe probe.
/// VLC opens URLs directly (including HTTP, RTSP, HLS) with its own demuxer —
/// no temp files, no format conversion, no external binary required.
///
/// ## Key improvements over AVPlayer+FFmpeg
/// - Seeking: frame-accurate, instant (`vlcPlayer.time = VLCTime(int:)`)
/// - Duration: available immediately from `vlcPlayer.media.length`
/// - MKV/TS/AVI/HEVC: all handled natively by libvlc
/// - No FFmpeg dependency (users don't need `brew install ffmpeg`)
@MainActor
@Observable
public final class PlayerCore {

    // MARK: - Observable state

    public private(set) var state: PlayerState = .idle
    public private(set) var currentChannel: Channel?
    public private(set) var isMuted: Bool = false
    public private(set) var volume: Float = 1.0
    public private(set) var isPiPActive: Bool = false   // reserved, custom PiP TBD

    /// Available audio tracks for the current media.
    public private(set) var availableAudioTracks: [VLCTrack] = []
    /// Available subtitle tracks for the current media.
    public private(set) var availableSubtitleTracks: [VLCTrack] = []
    /// Currently selected audio track ID (VLC index).
    public private(set) var selectedAudioTrackID: Int = -1
    /// Currently selected subtitle track ID (VLC index). -1 = disabled.
    public private(set) var selectedSubtitleTrackID: Int = -1

    /// Transient error banner (auto-dismisses after 5s).
    public private(set) var streamErrorBanner: String? = nil

    /// User-facing note when a provider/container cannot offer premium-grade seeking.
    public private(set) var playbackLimitationMessage: String? = nil

    /// Whether the current stream is live (not seekable) or VOD.
    public private(set) var isLiveStream: Bool = true

    /// Current playback position in seconds — stored so @Observable notifies SwiftUI.
    /// Updated every 0.5s by the UI timer when playing.
    public private(set) var currentTimeValue: TimeInterval = 0

    public private(set) var playbackRate: Float = 1.0
    private var pendingSeekPosition: Double? = nil
    private var pendingSeekRecoveryAttempt = 0
    private var activeSeekTarget: Double? = nil
    private var playbackTimeOffset: Double = 0
    private var preservedVODDuration: TimeInterval? = nil

    /// Convenience alias (same value, keeps external call sites working).
    public var currentTime: TimeInterval { currentTimeValue }

    /// Total duration in seconds. Returns 0 if unknown / live.
    public var duration: TimeInterval {
        if effectivePlaybackPlan?.route == .localHLSProxy, let preservedVODDuration {
            return preservedVODDuration
        }
        guard let media = vlcPlayer.media else { return 0 }
        let ms = media.length.intValue
        guard ms > 0 else { return 0 }
        let rawDuration = Double(ms) / 1000.0
        guard playbackTimeOffset > 0, effectivePlaybackPlan?.usesStartTime == true else {
            return max(rawDuration, preservedVODDuration ?? 0)
        }
        return max(rawDuration + playbackTimeOffset, preservedVODDuration ?? 0)
    }

    public var isPlaying: Bool { state == .playing }

    private var effectivePlaybackPlan: PlayerPlaybackConfig.PlaybackPlan? {
        if let currentPlaybackPlan { return currentPlaybackPlan }
        guard let currentChannel else { return nil }
        return PlayerPlaybackConfig.playbackPlan(for: currentChannel)
    }

    // MARK: - Channel navigation

    public var channelList: [Channel] = []
    public var currentXstreamCredentials: XstreamCredentials?

    // MARK: - Watch history callbacks

    public var onWatchSessionEnd: ((Channel, Date, Int) -> Void)?
    public var onProgressUpdate: ((Channel, Double, Double) -> Void)?

    @ObservationIgnored private var watchSessionEndObservers: [UUID: (Channel, Date, Int) -> Void] = [:]
    @ObservationIgnored private var progressUpdateObservers: [UUID: (Channel, Double, Double) -> Void] = [:]

    // MARK: - Quality presets (kept for API compat — VLC handles internally)

    public var selectedQuality: StreamQuality = StreamQuality.auto
    public let qualityPresets: [StreamQuality] = StreamQualityPreset.allCases.map { $0.quality }
    public private(set) var retryCount: Int = 0
    public let maxRetries: Int = 3

    // MARK: - Internal

    /// The underlying VLC media player.
    private let vlcPlayer: VLCMediaPlayer
    private let streamURLResolver = StreamRedirectResolver()
    private let localPlaybackProxy = LocalPlaybackProxy()

    /// Accessor for StreamStatsView — exposes VLC player for stats reading only.
    /// Do NOT use for playback control outside PlayerCore.
    public var vlcPlayerInternal: VLCMediaPlayer? { vlcPlayer }

    /// Bridge that forwards VLCMediaPlayerDelegate callbacks to PlayerCore on MainActor.
    private var bridge: VLCDelegateBridge?

    /// Monotonic token for the currently accepted playback session.
    @ObservationIgnored private var playbackSessionID: UInt64 = 0
    @ObservationIgnored private var pendingTransitionStopEvents: Int = 0
    @ObservationIgnored private weak var currentDrawable: AnyObject?
    @ObservationIgnored private var currentDrawableOwnerID: UUID?

    private let lastChannelStore = LastChannelStore()
    private var watchStartTime: Date?
    /// Kept as nil — actual UI refresh uses _uiDispatchSource (DispatchSourceTimer on .main).
    private var uiRefreshTimer: Timer?
    /// DispatchSourceTimer on .main — fires every 0.5s to update currentTimeValue.
    private var _uiDispatchSource: DispatchSourceTimer?
    /// 15s timer — reports progress to watch history.
    private var progressTimer: Timer?
    private var retryTask: Task<Void, Never>?
    private var loadingWatchdogTask: Task<Void, Never>?
    private var pendingPlaybackStartTask: Task<Void, Never>?
    private var pendingSeekTask: Task<Void, Never>?
    private var seekWatchdogTask: Task<Void, Never>?
    private var bannerDismissTask: Task<Void, Never>?
    private var seekGeneration: UInt64 = 0
    private var startupWatchdogRetryCount: Int = 0
    private var startupTimedOutSessionID: UInt64?
    @ObservationIgnored private var currentPlaybackPlan: PlayerPlaybackConfig.PlaybackPlan?
    /// True once VLC fires .playing at least once for the current media.
    /// Prevents later .buffering events from hiding the video with a spinner.
    private var hasEverPlayed: Bool = false

    // MARK: - Init

    public init() {
        self.vlcPlayer = VLCMediaPlayer(options: PlayerPlaybackConfig.libraryOptions)
        let b = VLCDelegateBridge(owner: self)
        self.bridge = b
        vlcPlayer.delegate = b
        // VLC volume is 0-200, where 100 = 100% (no amplification).
        // We normalise to 0.0-1.0 in our API.
        vlcPlayer.audio?.volume = 100
        setupRemoteCommands()
    }

    // MARK: - Drawable attachment (called by VLCVideoView)

    /// Attaches the VLC renderer to an NSView/UIView so video is drawn into it.
    public func attachDrawable(_ view: AnyObject) {
        attachDrawable(view, ownerID: UUID())
    }

    /// Attaches the VLC renderer to a drawable owned by a specific SwiftUI representable instance.
    public func attachDrawable(_ view: AnyObject, ownerID: UUID) {
        guard currentDrawableOwnerID != ownerID || currentDrawable !== view else { return }
        currentDrawable = view
        currentDrawableOwnerID = ownerID
        vlcPlayer.drawable = view
    }

    /// Detaches the renderer only when the dismantled view still owns the drawable.
    public func detachDrawable(_ view: AnyObject, ownerID: UUID) {
        guard currentDrawableOwnerID == ownerID, currentDrawable === view else { return }
        vlcPlayer.drawable = nil
        currentDrawable = nil
        currentDrawableOwnerID = nil
    }

    // MARK: - Watch history observers

    @discardableResult
    public func addWatchSessionEndObserver(_ observer: @escaping (Channel, Date, Int) -> Void) -> UUID {
        let id = UUID()
        watchSessionEndObservers[id] = observer
        return id
    }

    public func removeWatchSessionEndObserver(_ id: UUID) {
        watchSessionEndObservers.removeValue(forKey: id)
    }

    @discardableResult
    public func addProgressUpdateObserver(_ observer: @escaping (Channel, Double, Double) -> Void) -> UUID {
        let id = UUID()
        progressUpdateObservers[id] = observer
        return id
    }

    public func removeProgressUpdateObserver(_ id: UUID) {
        progressUpdateObservers.removeValue(forKey: id)
    }

    // MARK: - Media setup

    private struct PreparedPlaybackSource {
        let url: URL
        let playbackPlan: PlayerPlaybackConfig.PlaybackPlan
        let message: String?
    }

    private func makeMedia(
        for channel: Channel,
        playbackURL: URL,
        playbackPlan: PlayerPlaybackConfig.PlaybackPlan
    ) -> VLCMedia? {
        guard let media = VLCMedia(url: playbackURL) else { return nil }
        for option in PlayerPlaybackConfig.mediaOptions(plan: playbackPlan) {
            media.addOption(option)
        }
        return media
    }

    private func preparePlaybackSource(
        for channel: Channel,
        playbackPlan: PlayerPlaybackConfig.PlaybackPlan
    ) async -> PreparedPlaybackSource? {
        if playbackPlan.route == .localHLSProxy, let startPosition = playbackPlan.startPosition {
            let resolvedURL = await resolvedPlaybackURL(
                originalURL: channel.streamURL,
                playbackPlan: playbackPlan
            )

            do {
                let proxyURL = try await localPlaybackProxy.startHLS(
                    for: resolvedURL,
                    startPosition: startPosition,
                    userAgent: PlayerPlaybackConfig.httpUserAgent
                )
                print("[PlayerCore]   Local HLS proxy ready: \(proxyURL.path)")
                return PreparedPlaybackSource(
                    url: proxyURL,
                    playbackPlan: playbackPlan,
                    message: playbackPlan.limitationMessage
                )
            } catch {
                if error is CancellationError {
                    print("[PlayerCore]   Local HLS proxy preparation cancelled")
                    return nil
                }

                let fallbackPlan = PlayerPlaybackConfig.playbackPlan(
                    for: channel,
                    cachingProfile: playbackPlan.cachingProfile,
                    startPosition: startPosition,
                    localHLSProxyAvailable: false
                )
                let fallbackURL = await resolvedPlaybackURL(
                    originalURL: channel.streamURL,
                    playbackPlan: fallbackPlan
                )
                print("[PlayerCore]   Local HLS proxy unavailable: \(error.localizedDescription)")
                return PreparedPlaybackSource(
                    url: fallbackURL,
                    playbackPlan: fallbackPlan,
                    message: "Optimized seek unavailable — using provider-limited MKV seeking."
                )
            }
        }

        await localPlaybackProxy.stop()
        let playbackURL = await resolvedPlaybackURL(
            originalURL: channel.streamURL,
            playbackPlan: playbackPlan
        )
        return PreparedPlaybackSource(
            url: playbackURL,
            playbackPlan: playbackPlan,
            message: playbackPlan.limitationMessage
        )
    }

    private func resolvedPlaybackURL(
        originalURL: URL,
        playbackPlan: PlayerPlaybackConfig.PlaybackPlan
    ) async -> URL {
        guard playbackPlan.container == .matroska else { return originalURL }

        if let cached = await streamURLResolver.cachedURL(for: originalURL) {
            return cached
        }

        let resolved = await streamURLResolver.resolveFinalURL(for: originalURL)
        if resolved != originalURL {
            print("[PlayerCore]   MKV redirect resolved and cached")
        }
        return resolved
    }

    // MARK: - Public playback API

    /// Starts playback of `channel`. Debounced — rapid calls within 500ms are ignored.
    public func play(_ channel: Channel, startPosition: Double? = nil) {
        if currentChannel?.id == channel.id, startPosition == nil {
            if state == .playing {
                return
            }
            if state == .loading {
                print("[PlayerCore] Ignoring duplicate play request while current media is still loading")
                return
            }
        }

        playInternal(channel, startPosition: startPosition)
    }

    private func playInternal(
        _ channel: Channel,
        startPosition: Double?,
        resetRetryCount: Bool = true,
        endCurrentSession: Bool = true,
        seekRecoveryAttempt: Int = 0,
        allowLocalHLSProxy: Bool = true
    ) {
        lastChannelStore.save(channel)
        stopProgressTracking()
        if endCurrentSession {
            endWatchSession()
        }
        retryTask?.cancel()
        retryTask = nil
        pendingSeekTask?.cancel()
        pendingSeekTask = nil
        cancelSeekWatchdog()
        pendingPlaybackStartTask?.cancel()
        pendingPlaybackStartTask = nil
        cancelLoadingWatchdog()
        let sessionID = advancePlaybackSession()

        if currentChannel?.id != channel.id {
            preservedVODDuration = nil
        }
        currentChannel = channel
        if watchStartTime == nil {
            watchStartTime = .now
        }
        if resetRetryCount {
            retryCount = 0
            startupWatchdogRetryCount = 0
        }
        let cachingProfile = PlayerPlaybackConfig.cachingProfile(
            for: channel,
            startPosition: startPosition,
            startupRetryCount: startupWatchdogRetryCount
        )
        let playbackPlan = PlayerPlaybackConfig.playbackPlan(
            for: channel,
            cachingProfile: cachingProfile,
            startPosition: startPosition,
            localHLSProxyAvailable: allowLocalHLSProxy && LocalPlaybackProxy.isFFmpegAvailable
        )
        currentPlaybackPlan = playbackPlan
        playbackLimitationMessage = playbackPlan.limitationMessage
        isLiveStream = playbackPlan.isLiveStream
        playbackTimeOffset = playbackPlan.usesStartTime ? max(0, playbackPlan.startPosition ?? 0) : 0
        state = .loading
        hasEverPlayed = false
        currentTimeValue = max(0, playbackPlan.startPosition ?? 0)
        pendingSeekPosition = playbackPlan.startPosition
        pendingSeekRecoveryAttempt = seekRecoveryAttempt
        activeSeekTarget = playbackPlan.startPosition
        availableAudioTracks = []
        availableSubtitleTracks = []
        selectedAudioTrackID = -1
        selectedSubtitleTrackID = -1

        let url = channel.streamURL
        let ext = url.pathExtension.lowercased()

        print("[PlayerCore] Playing: \(channel.name)")
        print("[PlayerCore]   URL: \(url.aetherMaskedForLog)")
        print("[PlayerCore]   Extension: \(ext)")

        let networkCachingMilliseconds = PlayerPlaybackConfig.networkCachingMilliseconds(
            isLiveStream: playbackPlan.isLiveStream,
            cachingProfile: cachingProfile
        )
        let fileCachingMilliseconds = PlayerPlaybackConfig.fileCachingMilliseconds(
            isLiveStream: playbackPlan.isLiveStream,
            cachingProfile: cachingProfile
        )
        print("[PlayerCore]   Type: \(playbackPlan.isLiveStream ? "Live" : "VOD")")
        print("[PlayerCore]   Container: \(playbackPlan.container.logLabel)")
        print("[PlayerCore]   Playback route: \(playbackPlan.route.logLabel)")
        print("[PlayerCore]   Seek strategy: \(playbackPlan.seekStrategy.logLabel)")
        print("[PlayerCore]   Caching profile: \(cachingProfile.logLabel)")
        print("[PlayerCore]   Network caching: \(networkCachingMilliseconds)ms")
        print("[PlayerCore]   File caching: \(fileCachingMilliseconds)ms")

        pendingPlaybackStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            guard let self,
                  self.isCurrentPlaybackSession(sessionID),
                  self.currentChannel?.id == channel.id else { return }

            for _ in 0..<20 {
                if self.currentDrawable != nil { break }
                try? await Task.sleep(for: .milliseconds(25))
                guard !Task.isCancelled,
                      self.isCurrentPlaybackSession(sessionID),
                      self.currentChannel?.id == channel.id else { return }
            }

            let shouldPrepareBeforeStopping = playbackPlan.route == .localHLSProxy
            let preparedPlaybackSource: PreparedPlaybackSource?
            if shouldPrepareBeforeStopping {
                preparedPlaybackSource = await self.preparePlaybackSource(
                    for: channel,
                    playbackPlan: playbackPlan
                )
                guard !Task.isCancelled,
                      self.isCurrentPlaybackSession(sessionID),
                      self.currentChannel?.id == channel.id else { return }
            } else {
                preparedPlaybackSource = nil
            }

            if self.vlcPlayer.isPlaying || self.vlcPlayer.media != nil {
                self.pendingTransitionStopEvents += 1
                self.vlcPlayer.stop()
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled,
                      self.isCurrentPlaybackSession(sessionID),
                      self.currentChannel?.id == channel.id else { return }
            }

            let prepared: PreparedPlaybackSource?
            if let preparedPlaybackSource {
                prepared = preparedPlaybackSource
            } else {
                prepared = await self.preparePlaybackSource(
                    for: channel,
                    playbackPlan: playbackPlan
                )
            }
            guard !Task.isCancelled,
                  self.isCurrentPlaybackSession(sessionID),
                  self.currentChannel?.id == channel.id,
                  let prepared else { return }

            self.currentPlaybackPlan = prepared.playbackPlan
            self.playbackLimitationMessage = prepared.message
            self.isLiveStream = prepared.playbackPlan.isLiveStream
            self.playbackTimeOffset = prepared.playbackPlan.usesStartTime ? max(0, prepared.playbackPlan.startPosition ?? 0) : 0

            if prepared.url != channel.streamURL {
                print("[PlayerCore]   Resolved media URL: \(prepared.url.aetherMaskedForLog)")
            }

            guard let media = self.makeMedia(
                for: channel,
                playbackURL: prepared.url,
                playbackPlan: prepared.playbackPlan
            ) else {
                self.showStreamErrorBanner("Unable to load stream")
                self.state = .error("Unable to load stream")
                return
            }

            self.vlcPlayer.media = media
            self.vlcPlayer.play()
            self.disableTextTracksDuringStartup(sessionID: sessionID)
            self.pendingPlaybackStartTask = nil
            self.startLoadingWatchdog(sessionID: sessionID, channel: channel, playbackPlan: prepared.playbackPlan)
        }
    }

    // MARK: - Hot-Swapping Variants

    /// Seamlessly switches the underlying video URL without tearing down the player state (preserves watch session, etc).
    public func hotSwapVariant(to newChannel: Channel) {
        guard !isLiveStream else { return } // cannot reliably hot-swap live TV
        if newChannel.streamURL == currentChannel?.streamURL { return }
        
        // Retain previous variants if possible, just update the currently active stream
        var updatedChannel = newChannel
        if updatedChannel.availableVariants.isEmpty, let oldVariants = currentChannel?.availableVariants {
            updatedChannel.availableVariants = oldVariants
        }
        let targetTime = currentTime
        print("[PlayerCore] Hot-swapping stream variant at \(targetTime)s to: \(newChannel.streamURL.aetherMaskedForLog)")
        playInternal(
            updatedChannel,
            startPosition: targetTime,
            resetRetryCount: true,
            endCurrentSession: false
        )
    }

    public func resume() {
        guard case .paused = state else { return }
        vlcPlayer.play()
        state = .playing
        updateNowPlayingInfo()
    }

    public func pause() {
        guard case .playing = state else { return }
        vlcPlayer.pause()
        state = .paused
        updateNowPlayingInfo()
    }

    public func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused:  resume()
        default: break
        }
    }

    public func stop() {
        retryTask?.cancel()
        retryTask = nil
        pendingSeekTask?.cancel()
        pendingSeekTask = nil
        cancelSeekWatchdog()
        pendingPlaybackStartTask?.cancel()
        pendingPlaybackStartTask = nil
        cancelLoadingWatchdog()
        pendingTransitionStopEvents = 0
        advancePlaybackSession()
        stopProgressTracking()
        endWatchSession()
        vlcPlayer.stop()
        Task { await localPlaybackProxy.stop() }
        currentChannel = nil
        retryCount = 0
        startupWatchdogRetryCount = 0
        startupTimedOutSessionID = nil
        hasEverPlayed = false
        currentPlaybackPlan = nil
        playbackLimitationMessage = nil
        isLiveStream = true
        playbackTimeOffset = 0
        preservedVODDuration = nil
        currentTimeValue = 0
        pendingSeekPosition = nil
        pendingSeekRecoveryAttempt = 0
        activeSeekTarget = nil
        availableAudioTracks = []
        availableSubtitleTracks = []
        selectedAudioTrackID = -1
        selectedSubtitleTrackID = -1
        state = .idle
        publishNowPlayingInfo(nil)
    }

    public func toggleMute() {
        isMuted.toggle()
        vlcPlayer.audio?.isMuted = isMuted
    }

    public func setVolume(_ value: Float) {
        volume = max(0, min(1, value))
        // VLC audio volume: 0-200 (100 = unity gain, 200 = +6dB amplification)
        vlcPlayer.audio?.volume = Int32(volume * 100)
    }

    public func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        vlcPlayer.rate = rate
    }

    public func adjustVolume(delta: Float) {
        setVolume(volume + delta)
    }

    // MARK: - Seeking

    /// Seeks forward or backward by `seconds`. No-op for live streams.
    public func seek(by seconds: Double) {
        guard effectivePlaybackPlan?.canSeek == true else { return }
        let current = currentTime
        let target = max(0, current + seconds)
        userSeek(to: target)
    }

    /// Debounced seek used by scrub gestures. The UI position updates immediately,
    /// but VLC receives only the final settled target.
    public func requestSeek(to seconds: Double) {
        guard effectivePlaybackPlan?.canSeek == true, seconds.isFinite, seconds >= 0 else { return }
        let target = boundedSeekTime(seconds)
        currentTimeValue = target

        let debounceMilliseconds = effectivePlaybackPlan?.container == .matroska
            ? PlayerPlaybackConfig.matroskaSeekDebounceMilliseconds
            : PlayerPlaybackConfig.vodSeekDebounceMilliseconds

        pendingSeekTask?.cancel()
        pendingSeekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(debounceMilliseconds))
            guard !Task.isCancelled else { return }
            self?.performSeek(to: target)
        }
    }

    /// User-initiated seek to an absolute position (seconds).
    public func userSeek(to seconds: Double) {
        guard effectivePlaybackPlan?.canSeek == true, seconds.isFinite, seconds >= 0 else { return }
        pendingSeekTask?.cancel()
        pendingSeekTask = nil
        performSeek(to: boundedSeekTime(seconds))
    }

    private func boundedSeekTime(_ seconds: Double) -> Double {
        let mediaDuration = duration
        if mediaDuration > 0 {
            return min(max(0, seconds), mediaDuration)
        }
        return max(0, seconds)
    }

    private func performSeek(to seconds: Double, recoveryAttempt: Int = 0) {
        guard let playbackPlan = effectivePlaybackPlan, playbackPlan.canSeek else { return }
        print("[PlayerCore] Seek to \(String(format: "%.1f", seconds))s")
        currentTimeValue = seconds
        pendingSeekPosition = seconds
        activeSeekTarget = playbackPlan.usesPostSeekWatchdog ? seconds : nil
        if hasEverPlayed, playbackPlan.usesPostSeekWatchdog {
            state = .loading
        }

        if shouldRestartViaLocalProxy(for: playbackPlan) {
            restartMatroskaViaLocalProxy(at: seconds)
            return
        }

        let sessionID = playbackSessionID
        let seekID = nextSeekGeneration()
        let mediaDuration = duration

        if playbackPlan.seekStrategy == .resilientMatroska {
            playbackLimitationMessage = "This MKV provider has limited seeking. A different language/quality variant may seek faster."
            let ms = Int32(min(seconds * 1000, Double(Int32.max)))
            print("[PlayerCore]   Seek mode: resilient-matroska direct-time")
            vlcPlayer.time = VLCTime(int: ms)

            if mediaDuration > 0 {
                let position = min(max(seconds / mediaDuration, 0), 0.999_999)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(PlayerPlaybackConfig.matroskaPositionAssistDelayMilliseconds))
                    guard !Task.isCancelled,
                          let self,
                          self.isCurrentPlaybackSession(sessionID),
                          self.seekGeneration == seekID,
                          self.effectivePlaybackPlan?.seekStrategy == .resilientMatroska,
                          !self.hasSeekReachedTarget(current: self.vlcPlaybackSeconds, target: seconds) else { return }

                    print("[PlayerCore]   Seek assist: resilient-matroska position \(String(format: "%.4f", position))")
                    self.vlcPlayer.position = position
                }
            }

            startPostSeekWatchdog(
                target: seconds,
                sessionID: sessionID,
                seekID: seekID,
                recoveryAttempt: recoveryAttempt
            )
            return
        }

        if playbackPlan.prefersPositionSeek, mediaDuration > 0 {
            let position = min(max(seconds / mediaDuration, 0), 0.999_999)
            print("[PlayerCore]   Seek mode: \(playbackPlan.seekStrategy.logLabel) position \(String(format: "%.4f", position))")
            vlcPlayer.position = position
        } else {
            print("[PlayerCore]   Seek mode: \(playbackPlan.seekStrategy.logLabel) time")
            let ms = Int32(min(seconds * 1000, Double(Int32.max)))
            vlcPlayer.time = VLCTime(int: ms)
        }

        if playbackPlan.usesPostSeekWatchdog {
            startPostSeekWatchdog(
                target: seconds,
                sessionID: sessionID,
                seekID: seekID,
                recoveryAttempt: recoveryAttempt
            )
        } else if hasEverPlayed, state == .loading {
            state = .playing
        }
    }

    private func shouldRestartViaLocalProxy(for playbackPlan: PlayerPlaybackConfig.PlaybackPlan) -> Bool {
        guard !playbackPlan.isLiveStream else { return false }
        guard playbackPlan.container == .matroska else { return false }
        return playbackPlan.restartsPlaybackForSeek || LocalPlaybackProxy.isFFmpegAvailable
    }

    private func restartMatroskaViaLocalProxy(at seconds: Double) {
        guard let channel = currentChannel else { return }
        let knownDuration = duration
        if knownDuration > seconds {
            preservedVODDuration = knownDuration
        }
        activeSeekTarget = nil
        state = .loading
        playbackLimitationMessage = "Optimized MKV seeking is active."
        print("[PlayerCore]   Seek mode: local-hls-proxy restart at \(String(format: "%.1f", seconds))s")
        playInternal(
            channel,
            startPosition: seconds,
            resetRetryCount: false,
            endCurrentSession: false,
            allowLocalHLSProxy: true
        )
    }

    // MARK: - Audio / Subtitle track selection

    public func selectAudioTrack(_ track: VLCTrack) {
        vlcPlayer.selectTrack(at: track.id, type: .audio)
        selectedAudioTrackID = track.id
    }

    public func selectSubtitleTrack(_ track: VLCTrack?) {
        if let track {
            vlcPlayer.selectTrack(at: track.id, type: .text)
            selectedSubtitleTrackID = track.id
        } else {
            vlcPlayer.deselectAllTextTracks()
            selectedSubtitleTrackID = -1
        }
    }

    // MARK: - Channel navigation

    public func playNext() {
        guard let current = currentChannel,
              let idx = channelList.firstIndex(of: current),
              idx + 1 < channelList.count else { return }
        retryCount = 0
        playInternal(channelList[idx + 1], startPosition: nil)
    }

    public func playPrevious() {
        guard let current = currentChannel,
              let idx = channelList.firstIndex(of: current),
              idx > 0 else { return }
        retryCount = 0
        playInternal(channelList[idx - 1], startPosition: nil)
    }

    // MARK: - Last channel persistence

    public func restoreLastChannel() -> Channel? {
        lastChannelStore.restore()
    }

    // MARK: - PiP (stub — custom PiP TBD)

    public func startPiP() {
        // VLCKit doesn't integrate with macOS system PiP.
        // Custom floating window implementation planned for future milestone.
        print("[PlayerCore] PiP: not yet implemented with VLCKit")
    }

    public func setPiPActive(_ active: Bool) {
        isPiPActive = active
    }

    // MARK: - Error banner

    func showStreamErrorBanner(_ message: String) {
        streamErrorBanner = message
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.streamErrorBanner = nil
        }
    }

    /// Dismisses the error banner immediately (e.g. when user taps Retry).
    public func clearStreamErrorBanner() {
        bannerDismissTask?.cancel()
        streamErrorBanner = nil
    }

    // MARK: - VLC delegate callbacks (called by VLCDelegateBridge)

    func vlcStateChanged(_ vlcState: VLCMediaPlayerState, sessionID: UInt64) {
        guard isCurrentPlaybackSession(sessionID) else { return }
        // print("[PlayerCore] vlcStateChanged: \(vlcState.rawValue) — hasEverPlayed=\(hasEverPlayed)")
        switch vlcState {
        case .opening:
            if startupTimedOutSessionID != sessionID, !hasEverPlayed { state = .loading }
        case .buffering:
            // Only show loading overlay before first frame — afterwards keep .playing
            // so the video surface stays visible during mid-stream rebuffering.
            if startupTimedOutSessionID != sessionID, !hasEverPlayed { state = .loading }
        case .playing:
            finishStartupPlayback(sessionID: sessionID, reason: "VLC delegate reported .playing")
        case .paused:
            state = .paused
        case .stopped, .stopping:
            if startupTimedOutSessionID == sessionID { return }
            if pendingTransitionStopEvents > 0 {
                pendingTransitionStopEvents -= 1
                return
            }
            if currentChannel != nil {
                cancelLoadingWatchdog()
                stopProgressTracking()
                endWatchSession()
                state = .idle
            }
        case .error:
            guard currentChannel != nil else { return }
            if startupTimedOutSessionID == sessionID {
                print("[PlayerCore] VLC error after startup timeout — keeping timeout error")
                return
            }
            cancelLoadingWatchdog()
            stopProgressTracking()
            if currentPlaybackPlan?.route == .localHLSProxy, let channel = currentChannel {
                print("[PlayerCore] Local HLS proxy playback error — falling back to limited MKV seek")
                showStreamErrorBanner("Optimized seek failed — using provider seek")
                playInternal(
                    channel,
                    startPosition: pendingSeekPosition,
                    resetRetryCount: false,
                    endCurrentSession: false,
                    allowLocalHLSProxy: false
                )
                return
            }
            print("[PlayerCore] VLC error — scheduling retry")
            scheduleRetry(message: "Stream error — check your connection", sessionID: sessionID)
        @unknown default:
            print("[PlayerCore] Unknown VLC state: \(vlcState.rawValue)")
        }
    }

    func vlcMediaChanged(sessionID: UInt64) {
        guard isCurrentPlaybackSession(sessionID) else { return }
        // Reset tracks when media changes
        availableAudioTracks = []
        availableSubtitleTracks = []
    }

    func vlcTrackAdded(_ trackType: VLCMedia.TrackType, sessionID: UInt64) {
        guard isCurrentPlaybackSession(sessionID) else { return }
        if trackType == .text {
            vlcPlayer.deselectAllTextTracks()
            selectedSubtitleTrackID = -1
        }
    }

    private func disableTextTracksDuringStartup(sessionID: UInt64) {
        for delay in [0.0, 0.2, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentPlaybackSession(sessionID) else { return }
                    self.vlcPlayer.deselectAllTextTracks()
                    self.selectedSubtitleTrackID = -1
                }
            }
        }
    }

    private func finishStartupPlayback(sessionID: UInt64, reason: String? = nil) {
        guard isCurrentPlaybackSession(sessionID),
              startupTimedOutSessionID != sessionID,
              currentChannel != nil else { return }

        cancelLoadingWatchdog()
        startupTimedOutSessionID = nil
        hasEverPlayed = true

        guard state != .playing else { return }
        if let reason {
            print("[PlayerCore] \(reason) — forcing .playing")
        }

        state = .playing
        retryCount = 0
        if currentPlaybackPlan?.route != .localHLSProxy {
            let mediaMilliseconds = max(Int32(0), vlcPlayer.media?.length.intValue ?? 0)
            let mediaSeconds = Double(mediaMilliseconds) / 1000.0
            if mediaSeconds > 0, !isLiveStream {
                preservedVODDuration = max(preservedVODDuration ?? 0, mediaSeconds)
            }
        }

        let currentMilliseconds = max(Int32(0), vlcPlayer.time.intValue)
        if currentMilliseconds > 0 {
            let currentSeconds = displayedPlaybackSeconds(
                rawSeconds: Double(currentMilliseconds) / 1000.0
            )
            if let target = activeSeekTarget,
               abs(currentSeconds - target) > PlayerPlaybackConfig.postSeekTargetToleranceSeconds {
                currentTimeValue = target
            } else {
                currentTimeValue = currentSeconds
                activeSeekTarget = nil
            }
        }

        startProgressTracking()
        updateNowPlayingInfo()
        applyPendingSeekAfterStartup(sessionID: sessionID)
        scheduleTrackListRefresh(sessionID: sessionID)
    }

    private func applyPendingSeekAfterStartup(sessionID: UInt64) {
        guard let seekPos = pendingSeekPosition else { return }
        let recoveryAttempt = pendingSeekRecoveryAttempt
        pendingSeekPosition = nil
        pendingSeekRecoveryAttempt = 0

        if effectivePlaybackPlan?.usesStartTime == true {
            let displayed = displayedPlaybackSeconds()
            activeSeekTarget = nil
            currentTimeValue = max(seekPos, displayed)
            print("[PlayerCore] Start-time recovery active at \(String(format: "%.1f", currentTimeValue))s")
            return
        }

        if hasSeekReachedTarget(current: displayedPlaybackSeconds(), target: seekPos) {
            activeSeekTarget = nil
            currentTimeValue = displayedPlaybackSeconds()
            return
        }

        // Execute seek after a small delay to ensure buffer is ready.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlaybackSession(sessionID) else { return }
                self.performSeek(to: self.boundedSeekTime(seekPos), recoveryAttempt: recoveryAttempt)
            }
        }
    }

    private func nextSeekGeneration() -> UInt64 {
        seekGeneration &+= 1
        return seekGeneration
    }

    private func cancelSeekWatchdog() {
        seekWatchdogTask?.cancel()
        seekWatchdogTask = nil
        seekGeneration &+= 1
    }

    private func startPostSeekWatchdog(
        target: Double,
        sessionID: UInt64,
        seekID: UInt64,
        recoveryAttempt: Int
    ) {
        seekWatchdogTask?.cancel()
        seekWatchdogTask = Task { @MainActor [weak self] in
            let startedAt = Date()
            while Date().timeIntervalSince(startedAt) < PlayerPlaybackConfig.postSeekWatchdogTimeoutSeconds {
                try? await Task.sleep(for: .seconds(PlayerPlaybackConfig.postSeekWatchdogPollIntervalSeconds))
                guard !Task.isCancelled else { return }
                guard let self,
                      self.isCurrentPlaybackSession(sessionID),
                      self.seekGeneration == seekID else { return }

                let current = self.vlcPlaybackSeconds
                if self.hasSeekReachedTarget(current: current, target: target) {
                    self.finishPostSeekBuffering(target: target, sessionID: sessionID, seekID: seekID)
                    return
                }
            }

            guard !Task.isCancelled else { return }
            guard let self,
                  self.isCurrentPlaybackSession(sessionID),
                  self.seekGeneration == seekID else { return }

            let current = self.vlcPlaybackSeconds
            if self.hasSeekReachedTarget(current: current, target: target) {
                self.finishPostSeekBuffering(target: target, sessionID: sessionID, seekID: seekID)
                return
            }

            self.recoverStalledSeek(
                target: target,
                sessionID: sessionID,
                seekID: seekID,
                recoveryAttempt: recoveryAttempt
            )
        }
    }

    private var vlcPlaybackSeconds: Double {
        let milliseconds = max(Int32(0), vlcPlayer.time.intValue)
        return Double(milliseconds) / 1000.0
    }

    private func displayedPlaybackSeconds(rawSeconds: Double? = nil) -> Double {
        let raw = rawSeconds ?? vlcPlaybackSeconds
        guard playbackTimeOffset > 0 else { return raw }

        // VLCKit often reports time relative to :start-time after reopening MKV.
        // If it is clearly below the requested offset, project it back to full VOD time.
        if raw + PlayerPlaybackConfig.postSeekTargetToleranceSeconds < playbackTimeOffset {
            return playbackTimeOffset + raw
        }
        return raw
    }

    private func hasSeekReachedTarget(current: Double, target: Double) -> Bool {
        abs(current - target) <= PlayerPlaybackConfig.postSeekTargetToleranceSeconds
    }

    private func finishPostSeekBuffering(target: Double, sessionID: UInt64, seekID: UInt64) {
        guard isCurrentPlaybackSession(sessionID), seekGeneration == seekID else { return }
        seekWatchdogTask = nil
        activeSeekTarget = nil
        pendingSeekPosition = nil

        let current = displayedPlaybackSeconds()
        if current > 0 {
            currentTimeValue = current
        } else {
            currentTimeValue = target
        }

        if hasEverPlayed, state == .loading {
            state = .playing
            updateNowPlayingInfo()
        }
        print("[PlayerCore] Seek recovered at \(String(format: "%.1f", currentTimeValue))s")
    }

    private func recoverStalledSeek(
        target: Double,
        sessionID: UInt64,
        seekID: UInt64,
        recoveryAttempt: Int
    ) {
        guard isCurrentPlaybackSession(sessionID), seekGeneration == seekID else { return }
        guard effectivePlaybackPlan?.usesPostSeekWatchdog == true else {
            activeSeekTarget = nil
            seekWatchdogTask = nil
            if hasEverPlayed, state == .loading {
                state = .playing
            }
            return
        }
        guard recoveryAttempt < PlayerPlaybackConfig.postSeekMaxRecoveries,
              let channel = currentChannel else {
            activeSeekTarget = nil
            seekWatchdogTask = nil
            if hasEverPlayed, state == .loading {
                state = .playing
            }
            showStreamErrorBanner("Provider did not allow fast seek for this MKV")
            print("[PlayerCore] Seek watchdog gave up at \(String(format: "%.1f", target))s")
            return
        }

        print("[PlayerCore] Seek stalled at \(String(format: "%.1f", target))s — reopening VOD at target")
        showStreamErrorBanner("Still loading selected time — reopening stream")
        playInternal(
            channel,
            startPosition: target,
            resetRetryCount: false,
            endCurrentSession: false,
            seekRecoveryAttempt: recoveryAttempt + 1
        )
    }

    private func scheduleTrackListRefresh(sessionID: UInt64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlaybackSession(sessionID) else { return }
                self.refreshTrackLists()
            }
        }
    }

    // MARK: - Track lists

    private func refreshTrackLists() {
        // VLCKit 4: audioTracks / textTracks return [VLCMediaPlayerTrack]
        // trackName is non-optional in VLCKit 4 — no ?? needed.
        availableAudioTracks = vlcPlayer.audioTracks.enumerated().map { idx, t in
            VLCTrack(id: idx, name: t.trackName)
        }
        if let selIdx = vlcPlayer.audioTracks.firstIndex(where: { $0.isSelected }) {
            selectedAudioTrackID = selIdx
        }

        availableSubtitleTracks = vlcPlayer.textTracks.enumerated().map { idx, t in
            VLCTrack(id: idx, name: t.trackName)
        }
        if let selIdx = vlcPlayer.textTracks.firstIndex(where: { $0.isSelected }) {
            selectedSubtitleTrackID = selIdx
        }
    }

    // MARK: - Auto-retry

    private func startLoadingWatchdog(
        sessionID: UInt64,
        channel: Channel,
        playbackPlan: PlayerPlaybackConfig.PlaybackPlan
    ) {
        cancelLoadingWatchdog()
        let timeout = PlayerPlaybackConfig.startupTimeoutSeconds(cachingProfile: playbackPlan.cachingProfile)
        let pollInterval = PlayerPlaybackConfig.startupWatchdogPollIntervalSeconds
        let logInterval = PlayerPlaybackConfig.startupWatchdogLogIntervalSeconds

        loadingWatchdogTask = Task { @MainActor [weak self] in
            let startedAt = Date()
            var lastTimeMilliseconds: Int32?
            var lastPosition: Float?
            var nextStatusLogAt = startedAt.addingTimeInterval(logInterval)
            var lastLoggedIsPlaying: Bool?

            while true {
                try? await Task.sleep(for: .seconds(pollInterval))
                guard !Task.isCancelled else { return }
                guard let self,
                      self.isCurrentPlaybackSession(sessionID),
                      self.currentChannel?.id == channel.id,
                      !self.hasEverPlayed,
                      self.state == .loading else { return }

                let currentTimeMilliseconds = max(Int32(0), self.vlcPlayer.time.intValue)
                let rawPosition = Double(self.vlcPlayer.position)
                let currentPosition: Float = rawPosition.isFinite ? Float(max(0.0, rawPosition)) : 0
                let vlcIsPlaying = self.vlcPlayer.isPlaying
                let now = Date()
                let shouldLogStatus = lastLoggedIsPlaying != vlcIsPlaying || now >= nextStatusLogAt
                if shouldLogStatus {
                    let elapsed = now.timeIntervalSince(startedAt)
                    let seconds = Double(currentTimeMilliseconds) / 1000.0
                    let percent = Double(currentPosition * 100)
                    print("[PlayerCore] Startup watchdog waiting \(Int(elapsed))s/\(Int(timeout))s: isPlaying=\(vlcIsPlaying), state=\(self.state.logDescription), time=\(String(format: "%.1f", seconds))s, position=\(String(format: "%.2f", percent))%")
                    lastLoggedIsPlaying = vlcIsPlaying
                    nextStatusLogAt = now.addingTimeInterval(logInterval)
                }

                if playbackPlan.isLiveStream && vlcIsPlaying {
                    self.finishStartupPlayback(
                        sessionID: sessionID,
                        reason: "Startup watchdog observed active VLC playback"
                    )
                    return
                }

                if let previousTimeMilliseconds = lastTimeMilliseconds {
                    if currentTimeMilliseconds + PlayerPlaybackConfig.startupProgressMinimumTimeAdvanceMilliseconds < previousTimeMilliseconds {
                        lastTimeMilliseconds = currentTimeMilliseconds
                    } else if currentTimeMilliseconds - previousTimeMilliseconds >= PlayerPlaybackConfig.startupProgressMinimumTimeAdvanceMilliseconds {
                        let seconds = Double(currentTimeMilliseconds) / 1000.0
                        self.finishStartupPlayback(
                            sessionID: sessionID,
                            reason: "Startup watchdog observed playback time advancing to \(String(format: "%.1f", seconds))s"
                        )
                        return
                    }
                } else {
                    lastTimeMilliseconds = currentTimeMilliseconds
                }

                if let previousPosition = lastPosition {
                    if currentPosition + PlayerPlaybackConfig.startupProgressMinimumPositionAdvance < previousPosition {
                        lastPosition = currentPosition
                    } else if currentPosition - previousPosition >= PlayerPlaybackConfig.startupProgressMinimumPositionAdvance {
                        let percent = Double(currentPosition * 100)
                        self.finishStartupPlayback(
                            sessionID: sessionID,
                            reason: "Startup watchdog observed playback position advancing to \(String(format: "%.2f", percent))%"
                        )
                        return
                    }
                } else {
                    lastPosition = currentPosition
                }

                if Date().timeIntervalSince(startedAt) >= timeout {
                    break
                }
            }

            guard !Task.isCancelled else { return }
            guard let self,
                  self.isCurrentPlaybackSession(sessionID),
                  self.currentChannel?.id == channel.id,
                  !self.hasEverPlayed,
                  self.state == .loading else { return }

            self.loadingWatchdogTask = nil
            let streamKind = playbackPlan.isLiveStream ? "live" : "VOD"
            let currentTimeMilliseconds = max(Int32(0), self.vlcPlayer.time.intValue)
            let rawPosition = Double(self.vlcPlayer.position)
            let currentPosition: Float = rawPosition.isFinite ? Float(max(0.0, rawPosition)) : 0
            let seconds = Double(currentTimeMilliseconds) / 1000.0
            let percent = Double(currentPosition * 100)
            print("[PlayerCore] Startup watchdog fired after \(Int(timeout))s for \(streamKind) \(playbackPlan.container.logLabel): \(channel.streamURL.aetherMaskedForLog) (isPlaying=\(self.vlcPlayer.isPlaying), state=\(self.state.logDescription), time=\(String(format: "%.1f", seconds))s, position=\(String(format: "%.2f", percent))%)")

            if playbackPlan.route == .localHLSProxy {
                self.showStreamErrorBanner("Optimized seek stalled — falling back to provider seek")
                print("[PlayerCore] Local HLS proxy startup stalled — falling back to limited MKV seek")
                self.playInternal(
                    channel,
                    startPosition: playbackPlan.startPosition ?? self.pendingSeekPosition,
                    resetRetryCount: false,
                    endCurrentSession: false,
                    allowLocalHLSProxy: false
                )
                return
            }

            if self.startupWatchdogRetryCount < PlayerPlaybackConfig.startupWatchdogMaxRetries {
                self.startupWatchdogRetryCount += 1
                self.showStreamErrorBanner("Still buffering — retrying with stronger cache")
                print("[PlayerCore] Startup watchdog retry \(self.startupWatchdogRetryCount)/\(PlayerPlaybackConfig.startupWatchdogMaxRetries) with strengthened caching")
                self.playInternal(
                    channel,
                    startPosition: self.pendingSeekPosition,
                    resetRetryCount: false,
                    endCurrentSession: false
                )
                return
            }

            self.showStreamErrorBanner("Stream timed out while buffering")
            self.startupTimedOutSessionID = sessionID
            self.state = .error("Stream timed out while buffering")
            self.vlcPlayer.stop()
        }
    }

    private func cancelLoadingWatchdog() {
        loadingWatchdogTask?.cancel()
        loadingWatchdogTask = nil
    }

    private func scheduleRetry(message: String, sessionID: UInt64) {
        guard isCurrentPlaybackSession(sessionID) else { return }
        guard retryCount < maxRetries, let channel = currentChannel else {
            showStreamErrorBanner("Unable to load stream")
            state = .error("Unable to load stream")
            return
        }
        retryCount += 1
        let delay = Double(retryCount) * 2.0
        state = .loading
        print("[PlayerCore] Retry \(retryCount)/\(maxRetries) in \(Int(delay))s")

        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self,
                  self.isCurrentPlaybackSession(sessionID),
                  self.currentChannel?.id == channel.id else { return }
            let retryThroughLocalProxy = self.currentPlaybackPlan?.route != .localHLSProxy
            self.playInternal(
                channel,
                startPosition: self.pendingSeekPosition,
                resetRetryCount: false,
                endCurrentSession: false,
                allowLocalHLSProxy: retryThroughLocalProxy
            )
        }
    }

    // MARK: - Watch session / progress

    private func startProgressTracking() {
        let sessionID = playbackSessionID
        // UI source timer: 0.5s. DispatchSource callbacks are not guaranteed to
        // run on Swift's MainActor executor, so hop explicitly before touching state.
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
        let src = DispatchSource.makeTimerSource(queue: .main)
        src.schedule(deadline: .now() + 0.5, repeating: 0.5)
        src.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlaybackSession(sessionID) else { return }
                let ms = self.vlcPlayer.time.intValue
                let rawTime = Double(max(0, ms)) / 1000.0
                let t = self.displayedPlaybackSeconds(rawSeconds: rawTime)
                if let target = self.activeSeekTarget,
                   abs(t - target) > PlayerPlaybackConfig.postSeekTargetToleranceSeconds {
                    return
                }
                if abs(t - self.currentTimeValue) > 0.1 {
                    self.currentTimeValue = t

                    // VLC 4 sometimes never re-emits .playing after buffering ends.
                    // If time is advancing but UI is stuck on .loading, force .playing.
                    if self.state == .loading {
                        print("[PlayerCore] Time advancing during .loading — forcing .playing")
                        self.cancelLoadingWatchdog()
                        self.startupTimedOutSessionID = nil
                        self.state = .playing
                        self.hasEverPlayed = true
                        self.retryCount = 0
                        self.updateNowPlayingInfo()
                        let trackSessionID = self.playbackSessionID
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            Task { @MainActor [weak self] in
                                guard let self, self.isCurrentPlaybackSession(trackSessionID) else { return }
                                self.refreshTrackLists()
                            }
                        }
                    }
                }
            }
        }
        src.resume()
        // Wrap DispatchSourceTimer in a bridge so we keep one uiRefreshTimer variable
        _uiDispatchSource = src

        // Progress timer: every 15s — reports to watch history
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isCurrentPlaybackSession(sessionID),
                      let channel = self.currentChannel else { return }
                self.notifyProgressUpdate(channel: channel, watched: self.currentTimeValue, total: self.duration)
            }
        }
    }


    private func stopProgressTracking() {
        _uiDispatchSource?.cancel()
        _uiDispatchSource = nil
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func endWatchSession() {
        guard let channel = currentChannel, let start = watchStartTime else { return }
        let elapsed = Int(Date.now.timeIntervalSince(start))
        if elapsed > 5 {
            notifyWatchSessionEnd(channel: channel, start: start, duration: elapsed)
        }
        watchStartTime = nil
    }

    @discardableResult
    private func advancePlaybackSession() -> UInt64 {
        playbackSessionID &+= 1
        startupTimedOutSessionID = nil
        bridge?.playbackSessionID = playbackSessionID
        return playbackSessionID
    }

    private func isCurrentPlaybackSession(_ sessionID: UInt64) -> Bool {
        sessionID == playbackSessionID
    }

    private func notifyWatchSessionEnd(channel: Channel, start: Date, duration: Int) {
        onWatchSessionEnd?(channel, start, duration)
        for observer in watchSessionEndObservers.values {
            observer(channel, start, duration)
        }
    }

    private func notifyProgressUpdate(channel: Channel, watched: Double, total: Double) {
        onProgressUpdate?(channel, watched, total)
        for observer in progressUpdateObservers.values {
            observer(channel, watched, total)
        }
    }

    // MARK: - Now Playing (Lock Screen / Control Center)

    private func publishNowPlayingInfo(_ info: [String: Any]?) {
        #if os(macOS)
        // MPNowPlayingInfoCenter can trip libdispatch queue assertions under Xcode
        // on macOS. Playback reliability is more important than lock-screen metadata.
        return
        #else
        let snapshot = info.map { NSDictionary(dictionary: $0) }
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = snapshot as? [String: Any]
        }
        #endif
    }

    private func updateNowPlayingInfo() {
        guard let channel = currentChannel else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.name,
            MPNowPlayingInfoPropertyIsLiveStream: isLiveStream,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
        ]
        if let logo = channel.logoURL {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: CGSize(width: 512, height: 512)) { _ in
                #if canImport(AppKit)
                return (try? Data(contentsOf: logo)).flatMap { NSImage(data: $0) } ?? NSImage()
                #else
                return (try? Data(contentsOf: logo)).flatMap { UIImage(data: $0) } ?? UIImage()
                #endif
            }
        }
        publishNowPlayingInfo(info)
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.userSeek(to: e.positionTime) }
            return .success
        }
    }
}

// MARK: - VLCDelegateBridge

/// Non-isolated NSObject that conforms to VLCMediaPlayerDelegate.
/// VLC calls delegate methods on a background thread — this bridge dispatches them
/// to MainActor so PlayerCore (which is @MainActor) can handle them safely.
final class VLCDelegateBridge: NSObject, VLCMediaPlayerDelegate, @unchecked Sendable {
    // nonisolated(unsafe): we only ever access this inside Task { @MainActor }, which IS safe.
    nonisolated(unsafe) private weak var owner: PlayerCore?
    nonisolated(unsafe) var playbackSessionID: UInt64 = 0

    init(owner: PlayerCore) {
        self.owner = owner
    }

    // MARK: - VLCMediaPlayerDelegate (exact Obj-C signatures from VLCMediaPlayer.h)

    /// `- (void)mediaPlayerStateChanged:(VLCMediaPlayerState)newState;`
    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        let sessionID = playbackSessionID
        Task { @MainActor [weak owner] in
            owner?.vlcStateChanged(newState, sessionID: sessionID)
        }
    }

    func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
        let sessionID = playbackSessionID
        Task { @MainActor [weak owner] in
            owner?.vlcTrackAdded(trackType, sessionID: sessionID)
        }
    }

    /// `- (void)mediaPlayerLengthChanged:(int64_t)length;`
    func mediaPlayerLengthChanged(_ length: Int64) {
        // Duration is read lazily from vlcPlayer.length in PlayerCore — no action needed.
    }

    /// `- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification;`
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // UI timer handles currentTimeValue updates every 0.5s — no extra action needed.
    }
}

// MARK: - Stream redirect resolution

private actor StreamRedirectResolver {
    private var cache: [String: URL] = [:]

    func cachedURL(for originalURL: URL) -> URL? {
        cache[originalURL.absoluteString]
    }

    func resolveFinalURL(for originalURL: URL) async -> URL {
        let key = originalURL.absoluteString
        if let cached = cache[key] {
            return cached
        }

        let resolved = await StreamURLProbe.resolveFinalURL(for: originalURL)
        if resolved != originalURL {
            cache[key] = resolved
        }
        return resolved
    }
}

private enum StreamURLProbe {
    static func resolveFinalURL(for originalURL: URL) async -> URL {
        let redirectedURL: URL? = await withCheckedContinuation { continuation in
            let delegate = StreamURLProbeDelegate(continuation: continuation)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = PlayerPlaybackConfig.redirectProbeTimeoutSeconds
            config.timeoutIntervalForResource = PlayerPlaybackConfig.redirectProbeTimeoutSeconds
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData

            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: queue)

            var request = URLRequest(url: originalURL)
            request.httpMethod = "GET"
            request.timeoutInterval = PlayerPlaybackConfig.redirectProbeTimeoutSeconds
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            request.setValue(PlayerPlaybackConfig.httpUserAgent, forHTTPHeaderField: "User-Agent")

            delegate.onFinish = {
                session.invalidateAndCancel()
            }
            session.dataTask(with: request).resume()
        }
        return redirectedURL ?? originalURL
    }
}

private final class StreamURLProbeDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<URL?, Never>
    var onFinish: (() -> Void)?

    init(continuation: CheckedContinuation<URL?, Never>) {
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        resume(request.url)
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        resume(nil)
        completionHandler(.cancel)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        resume(nil)
    }

    private func resume(_ url: URL?) {
        lock.lock()
        if didResume {
            lock.unlock()
            return
        }
        didResume = true
        let finish = onFinish
        lock.unlock()

        continuation.resume(returning: url)
        finish?()
    }
}

private extension URL {
    var aetherMaskedForLog: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return "<invalid-url>"
        }

        if components.user != nil {
            components.user = "***"
        }
        if components.password != nil {
            components.password = "***"
        }

        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                let lowerName = item.name.lowercased()
                if lowerName == "username" || lowerName == "password" || lowerName == "user" || lowerName == "pass" {
                    return URLQueryItem(name: item.name, value: "***")
                }
                return item
            }
        }

        var segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let markerIndex = segments.firstIndex(where: { segment in
            let lower = segment.lowercased()
            return lower == "live" || lower == "movie" || lower == "series"
        }), segments.indices.contains(markerIndex + 2) {
            segments[markerIndex + 1] = "***"
            segments[markerIndex + 2] = "***"
            components.percentEncodedPath = segments.joined(separator: "/")
        }

        return components.url?.absoluteString ?? "<masked-url>"
    }
}
