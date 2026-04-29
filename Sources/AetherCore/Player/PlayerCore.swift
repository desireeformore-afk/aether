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
        case strengthened
    }

    static let liveNetworkCachingMilliseconds = 1500
    static let liveFileCachingMilliseconds = 1000
    static let liveLiveCachingMilliseconds = 1500
    static let vodNetworkCachingMilliseconds = 6000
    static let vodFileCachingMilliseconds = 6000
    static let strengthenedLiveNetworkCachingMilliseconds = 2500
    static let strengthenedLiveFileCachingMilliseconds = 1500
    static let strengthenedLiveLiveCachingMilliseconds = 2500
    static let strengthenedVODNetworkCachingMilliseconds = 12000
    static let strengthenedVODFileCachingMilliseconds = 12000
    static let startupPlaybackTimeoutSeconds = 35.0
    static let strengthenedStartupPlaybackTimeoutSeconds = 50.0
    static let startupWatchdogMaxRetries = 1
    static let startupWatchdogPollIntervalSeconds = 0.5
    static let startupWatchdogLogIntervalSeconds = 5.0
    static let startupProgressMinimumTimeAdvanceMilliseconds: Int32 = 250
    static let startupProgressMinimumPositionAdvance: Float = 0.0001
    static let httpUserAgent = "VLC/3.0.20 LibVLC/3.0.20"
    private static let vodExtensions: Set<String> = ["mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v"]

    static func networkCachingMilliseconds(isLiveStream: Bool, cachingProfile: CachingProfile = .standard) -> Int {
        switch (isLiveStream, cachingProfile) {
        case (true, .standard): return liveNetworkCachingMilliseconds
        case (true, .strengthened): return strengthenedLiveNetworkCachingMilliseconds
        case (false, .standard): return vodNetworkCachingMilliseconds
        case (false, .strengthened): return strengthenedVODNetworkCachingMilliseconds
        }
    }

    static func fileCachingMilliseconds(isLiveStream: Bool, cachingProfile: CachingProfile = .standard) -> Int {
        switch (isLiveStream, cachingProfile) {
        case (true, .standard): return liveFileCachingMilliseconds
        case (true, .strengthened): return strengthenedLiveFileCachingMilliseconds
        case (false, .standard): return vodFileCachingMilliseconds
        case (false, .strengthened): return strengthenedVODFileCachingMilliseconds
        }
    }

    static func liveCachingMilliseconds(isLiveStream: Bool, cachingProfile: CachingProfile = .standard) -> Int {
        switch (isLiveStream, cachingProfile) {
        case (true, .standard): return liveLiveCachingMilliseconds
        case (true, .strengthened): return strengthenedLiveLiveCachingMilliseconds
        case (false, .standard): return vodNetworkCachingMilliseconds
        case (false, .strengthened): return strengthenedVODNetworkCachingMilliseconds
        }
    }

    static func startupTimeoutSeconds(cachingProfile: CachingProfile) -> Double {
        cachingProfile == .strengthened ? strengthenedStartupPlaybackTimeoutSeconds : startupPlaybackTimeoutSeconds
    }

    static func isLiveStream(channel: Channel) -> Bool {
        switch channel.contentType {
        case .liveTV:
            let ext = channel.streamURL.pathExtension.lowercased()
            return !vodExtensions.contains(ext)
        case .movie, .series:
            return false
        }
    }

    static func mediaOptions(isLiveStream: Bool, cachingProfile: CachingProfile) -> [String] {
        [
            "--network-caching=\(networkCachingMilliseconds(isLiveStream: isLiveStream, cachingProfile: cachingProfile))",
            "--file-caching=\(fileCachingMilliseconds(isLiveStream: isLiveStream, cachingProfile: cachingProfile))",
            "--live-caching=\(liveCachingMilliseconds(isLiveStream: isLiveStream, cachingProfile: cachingProfile))",
            "--http-reconnect",
            "--http-continuous",
            "--rtsp-tcp",
            "--http-user-agent=\(httpUserAgent)"
        ]
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

    /// Whether the current stream is live (not seekable) or VOD.
    public private(set) var isLiveStream: Bool = true

    /// Current playback position in seconds — stored so @Observable notifies SwiftUI.
    /// Updated every 0.5s by the UI timer when playing.
    public private(set) var currentTimeValue: TimeInterval = 0

    public private(set) var playbackRate: Float = 1.0
    private var pendingSeekPosition: Double? = nil

    /// Convenience alias (same value, keeps external call sites working).
    public var currentTime: TimeInterval { currentTimeValue }

    /// Total duration in seconds. Returns 0 if unknown / live.
    public var duration: TimeInterval {
        guard let media = vlcPlayer.media else { return 0 }
        let ms = media.length.intValue
        return ms > 0 ? Double(ms) / 1000.0 : 0
    }

    public var isPlaying: Bool { state == .playing }

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
    private let vlcPlayer: VLCMediaPlayer = VLCMediaPlayer()

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
    private var bannerDismissTask: Task<Void, Never>?
    private var startupWatchdogRetryCount: Int = 0
    private var startupTimedOutSessionID: UInt64?
    /// True once VLC fires .playing at least once for the current media.
    /// Prevents later .buffering events from hiding the video with a spinner.
    private var hasEverPlayed: Bool = false

    // MARK: - Init

    public init() {
        let b = VLCDelegateBridge(owner: self)
        self.bridge = b
        vlcPlayer.delegate = b
        // VLC volume is 0-200, where 100 = 100% (no amplification).
        // We normalise to 0.0-1.0 in our API.
        vlcPlayer.audio?.volume = 100
        setupRemoteCommands()
    }

    // MARK: - NSView attachment (called by VLCVideoView)

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

    private func makeMedia(
        for channel: Channel,
        isLiveStream: Bool,
        cachingProfile: PlayerPlaybackConfig.CachingProfile
    ) -> VLCMedia? {
        guard let media = VLCMedia(url: channel.streamURL) else { return nil }
        for option in PlayerPlaybackConfig.mediaOptions(isLiveStream: isLiveStream, cachingProfile: cachingProfile) {
            media.addOption(option)
        }
        return media
    }

    // MARK: - Public playback API

    /// Starts playback of `channel`. Debounced — rapid calls within 500ms are ignored.
    public func play(_ channel: Channel, startPosition: Double? = nil) {
        // Same channel already playing — skip
        if currentChannel?.id == channel.id, state == .playing { return }

        playInternal(channel, startPosition: startPosition)
    }

    private func playInternal(
        _ channel: Channel,
        startPosition: Double?,
        resetRetryCount: Bool = true,
        endCurrentSession: Bool = true
    ) {
        lastChannelStore.save(channel)
        stopProgressTracking()
        if endCurrentSession {
            endWatchSession()
        }
        retryTask?.cancel()
        retryTask = nil
        cancelLoadingWatchdog()

        let shouldStopExistingMedia = vlcPlayer.isPlaying || vlcPlayer.media != nil
        let sessionID = advancePlaybackSession()

        // Stop any ongoing VLC playback cleanly
        if shouldStopExistingMedia {
            pendingTransitionStopEvents += 1
            vlcPlayer.stop()
        }

        currentChannel = channel
        if watchStartTime == nil {
            watchStartTime = .now
        }
        state = .loading
        if resetRetryCount {
            retryCount = 0
            startupWatchdogRetryCount = 0
        }
        hasEverPlayed = false
        currentTimeValue = 0
        pendingSeekPosition = startPosition
        availableAudioTracks = []
        availableSubtitleTracks = []
        selectedAudioTrackID = -1
        selectedSubtitleTrackID = -1

        let url = channel.streamURL
        let ext = url.pathExtension.lowercased()

        print("[PlayerCore] Playing: \(channel.name)")
        print("[PlayerCore]   URL: \(url.aetherMaskedForLog)")
        print("[PlayerCore]   Extension: \(ext)")

        // VOD = movies/series or seekable file containers. Live = indefinite TS/m3u8 streams.
        isLiveStream = PlayerPlaybackConfig.isLiveStream(channel: channel)
        let cachingProfile: PlayerPlaybackConfig.CachingProfile = startupWatchdogRetryCount > 0 ? .strengthened : .standard
        let networkCachingMilliseconds = PlayerPlaybackConfig.networkCachingMilliseconds(
            isLiveStream: isLiveStream,
            cachingProfile: cachingProfile
        )
        let fileCachingMilliseconds = PlayerPlaybackConfig.fileCachingMilliseconds(
            isLiveStream: isLiveStream,
            cachingProfile: cachingProfile
        )
        print("[PlayerCore]   Type: \(isLiveStream ? "Live" : "VOD")")
        print("[PlayerCore]   Caching profile: \(cachingProfile == .strengthened ? "strengthened" : "standard")")
        print("[PlayerCore]   Network caching: \(networkCachingMilliseconds)ms")
        print("[PlayerCore]   File caching: \(fileCachingMilliseconds)ms")

        guard let media = makeMedia(for: channel, isLiveStream: isLiveStream, cachingProfile: cachingProfile) else {
            showStreamErrorBanner("Unable to load stream")
            state = .error("Unable to load stream")
            return
        }

        vlcPlayer.media = media
        vlcPlayer.play()
        startLoadingWatchdog(sessionID: sessionID, channel: channel, cachingProfile: cachingProfile)
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
        guard let media = makeMedia(for: updatedChannel, isLiveStream: false, cachingProfile: .standard) else {
            showStreamErrorBanner("Unable to load selected stream")
            return
        }

        let targetTime = currentTime
        retryTask?.cancel()
        retryTask = nil
        cancelLoadingWatchdog()
        let shouldStopExistingMedia = vlcPlayer.isPlaying || vlcPlayer.media != nil
        let sessionID = advancePlaybackSession()
        print("[PlayerCore] Hot-swapping stream variant at \(targetTime)s to: \(newChannel.streamURL.aetherMaskedForLog)")

        state = .loading
        hasEverPlayed = false
        startupWatchdogRetryCount = 0
        pendingSeekPosition = targetTime

        currentChannel = updatedChannel

        if shouldStopExistingMedia {
            pendingTransitionStopEvents += 1
            vlcPlayer.stop()
        }

        vlcPlayer.media = media
        vlcPlayer.play()
        startLoadingWatchdog(sessionID: sessionID, channel: updatedChannel, cachingProfile: .standard)
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
        cancelLoadingWatchdog()
        pendingTransitionStopEvents = 0
        advancePlaybackSession()
        stopProgressTracking()
        endWatchSession()
        vlcPlayer.stop()
        currentChannel = nil
        retryCount = 0
        startupWatchdogRetryCount = 0
        startupTimedOutSessionID = nil
        hasEverPlayed = false
        currentTimeValue = 0
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
        guard !isLiveStream else { return }
        let current = currentTime
        let target = max(0, current + seconds)
        userSeek(to: target)
    }

    /// User-initiated seek to an absolute position (seconds).
    public func userSeek(to seconds: Double) {
        guard !isLiveStream, seconds.isFinite, seconds >= 0 else { return }
        print("[PlayerCore] Seek to \(String(format: "%.1f", seconds))s")
        let ms = Int32(min(seconds * 1000, Double(Int32.max)))
        vlcPlayer.time = VLCTime(int: ms)
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

        let currentMilliseconds = max(Int32(0), vlcPlayer.time.intValue)
        if currentMilliseconds > 0 {
            currentTimeValue = Double(currentMilliseconds) / 1000.0
        }

        startProgressTracking()
        updateNowPlayingInfo()
        applyPendingSeekAfterStartup(sessionID: sessionID)
        scheduleTrackListRefresh(sessionID: sessionID)
    }

    private func applyPendingSeekAfterStartup(sessionID: UInt64) {
        guard let seekPos = pendingSeekPosition else { return }
        pendingSeekPosition = nil

        // Execute seek after a small delay to ensure buffer is ready.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlaybackSession(sessionID) else { return }
                self.userSeek(to: seekPos)
            }
        }
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
        cachingProfile: PlayerPlaybackConfig.CachingProfile
    ) {
        cancelLoadingWatchdog()
        let timeout = PlayerPlaybackConfig.startupTimeoutSeconds(cachingProfile: cachingProfile)
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
            let streamKind = self.isLiveStream ? "live" : "VOD"
            let currentTimeMilliseconds = max(Int32(0), self.vlcPlayer.time.intValue)
            let rawPosition = Double(self.vlcPlayer.position)
            let currentPosition: Float = rawPosition.isFinite ? Float(max(0.0, rawPosition)) : 0
            let seconds = Double(currentTimeMilliseconds) / 1000.0
            let percent = Double(currentPosition * 100)
            print("[PlayerCore] Startup watchdog fired after \(Int(timeout))s for \(streamKind): \(channel.streamURL.aetherMaskedForLog) (isPlaying=\(self.vlcPlayer.isPlaying), state=\(self.state.logDescription), time=\(String(format: "%.1f", seconds))s, position=\(String(format: "%.2f", percent))%)")

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
            self.playInternal(
                channel,
                startPosition: self.pendingSeekPosition,
                resetRetryCount: false,
                endCurrentSession: false
            )
        }
    }

    // MARK: - Watch session / progress

    private func startProgressTracking() {
        let sessionID = playbackSessionID
        // UI source timer: 0.5s on DispatchQueue.main so the closure runs on the
        // main thread and can access @MainActor-isolated properties directly.
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
        let src = DispatchSource.makeTimerSource(queue: .main)
        src.schedule(deadline: .now() + 0.5, repeating: 0.5)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard self.isCurrentPlaybackSession(sessionID) else { return }
                let ms = self.vlcPlayer.time.intValue
                let t = Double(max(0, ms)) / 1000.0
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
        let snapshot = info.map { NSDictionary(dictionary: $0) }
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = snapshot as? [String: Any]
        }
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

    /// `- (void)mediaPlayerLengthChanged:(int64_t)length;`
    func mediaPlayerLengthChanged(_ length: Int64) {
        // Duration is read lazily from vlcPlayer.length in PlayerCore — no action needed.
    }

    /// `- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification;`
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // UI timer handles currentTimeValue updates every 0.5s — no extra action needed.
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
