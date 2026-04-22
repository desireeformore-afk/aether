@preconcurrency import AVFoundation
@preconcurrency import Combine
import Foundation
import MediaPlayer

/// Playback state of ``PlayerCore``.
public enum PlayerState: Sendable, Equatable {
    /// No channel is loaded.
    case idle
    /// Channel is loading.
    case loading
    /// Channel is playing.
    case playing
    /// Playback is paused.
    case paused
    /// Playback failed with an error message.
    case error(String)
}

/// A `@MainActor` wrapper around `AVPlayer` for IPTV stream playback.
///
/// Manages IPTV channel playback with support for:
/// - Play/pause/stop/mute/volume control
/// - Picture-in-Picture (PiP) delegation
/// - Channel navigation (next/previous)
/// - Auto-retry on stall/error (max 3x with exponential backoff)
/// - Watch session tracking
/// - Stream quality selection
///
/// ## Topics
///
/// ### Creating a Player
/// - ``init()``
///
/// ### Playback Control
/// - ``play(_:)``
/// - ``stop()``
/// - ``togglePlayPause()``
/// - ``playNext()``
/// - ``playPrevious()``
///
/// ### Audio Control
/// - ``toggleMute()``
/// - ``setVolume(_:)``
///
/// ### State
/// - ``state``
/// - ``currentChannel``
/// - ``isMuted``
/// - ``volume``
/// - ``isPiPActive``
///
/// ### Quality Selection
/// - ``selectedQuality``
/// - ``qualityPresets``
///
/// ### Channel Navigation
/// - ``channelList``
///
/// ## Example
///
/// ```swift
/// let player = PlayerCore()
/// if let url = URL(string: "http://...") {
///     let channel = Channel(name: "BBC One", streamURL: url)
///     player.play(channel)
/// }
/// ```
@MainActor
@Observable
public final class PlayerCore {

    // MARK: - Published state

    /// Current playback state.
    public private(set) var state: PlayerState = .idle

    /// Currently playing channel, if any.
    public private(set) var currentChannel: Channel?

    /// Whether audio is muted.
    public private(set) var isMuted: Bool = false

    /// Audio volume (0.0 to 1.0).
    public private(set) var volume: Float = 1.0

    /// Whether Picture-in-Picture is active.
    public private(set) var isPiPActive: Bool = false

    /// Available audio tracks for the current item.
    public private(set) var availableAudioOptions: [AVMediaSelectionOption] = []
    /// Available subtitle/caption tracks for the current item.
    public private(set) var availableSubtitleOptions: [AVMediaSelectionOption] = []
    /// Currently selected audio option.
    public private(set) var selectedAudioOption: AVMediaSelectionOption? = nil
    /// Currently selected subtitle option.
    public private(set) var selectedSubtitleOption: AVMediaSelectionOption? = nil
    private var audioSelectionGroup: AVMediaSelectionGroup? = nil
    private var subtitleSelectionGroup: AVMediaSelectionGroup? = nil

    /// Transient banner message shown after all retries exhausted (auto-dismisses after 5s).
    public private(set) var streamErrorBanner: String? = nil

    /// Current playback time in seconds.
    public var currentTime: TimeInterval {
        player.currentTime().seconds
    }

    /// Whether the current stream is live (true) or VOD with seekable duration (false).
    public private(set) var isLiveStream: Bool = true

    /// Whether playback is currently active.
    public var isPlaying: Bool {
        state == .playing
    }

    /// Selected stream quality preset.
    public var selectedQuality: StreamQuality = StreamQuality.auto {
        didSet { StreamQualityService().apply(selectedQuality, to: player) }
    }

    /// Current retry attempt count (0 = first play, >0 = retrying).
    public private(set) var retryCount: Int = 0

    /// Maximum number of auto-retries before giving up.
    public let maxRetries: Int = 3

    /// Available quality presets.
    public let qualityPresets: [StreamQuality] = StreamQualityPreset.allCases.map { $0.quality }

    // MARK: - Channel navigation support

    /// The ordered list of channels the user is currently browsing.
    /// Set by `ChannelListView` when a playlist is loaded.
    public var channelList: [Channel] = []

    /// Set by the playlist sidebar when an Xtream playlist is loaded.
    /// Used to show Series and VOD browser buttons.
    public var currentXstreamCredentials: XstreamCredentials?

    // MARK: - Watch history callbacks

    /// Called when a watch session ends (channel switched or stopped).
    /// Parameters: (channel, startDate, durationSeconds)
    public var onWatchSessionEnd: ((Channel, Date, Int) -> Void)?

    /// Called every 15 seconds during playback to update watch progress.
    /// Parameters: (channelID, watchedSeconds, durationSeconds)
    public var onProgressUpdate: ((UUID, Double, Double) -> Void)?

    // MARK: - Internal

    /// The underlying AVPlayer instance.
    public let player: AVPlayer = AVPlayer()

    // Warmup buffer — preloads the next channel so switching is near-instant
    private var warmupPlayer: AVPlayer? = nil
    private var warmupChannel: Channel? = nil

    private var statusObserver: AnyCancellable?
    private var stallObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var isRetrying: Bool = false
    /// The AVPlayerItem that triggered the current pending retry (prevents duplicate retries
    /// when both .status == .failed and AVPlayerItemFailedToPlayToEndTime fire for the same item).
    private weak var retrySourceItem: AVPlayerItem?

    /// Blocks retry when HTTP 400 error is detected.
    private var shouldBlockRetry: Bool = false

    /// URLs that failed via FFmpeg proxy this session — skip automatic retry for these.
    private var failedProxyURLs = Set<String>()

    /// FFmpeg HLS proxy — remuxes TS/MKV to local HLS segments for AVPlayer
    private var hlsProxy: LocalHLSProxy?

    /// True while a LocalHLSProxy is in the process of starting up (between proxy creation and
    /// first-segment ready). Guards against rapid duplicate play() calls that stop the proxy
    /// before FFmpeg has a chance to write its first segment.
    private var isLoadingProxy: Bool = false

    /// Timestamp of the last accepted play() call — used to debounce rapid consecutive calls.
    private var lastPlayRequestedAt: Date = .distantPast

    /// Tracks when the current channel started playing.
    private var watchStartTime: Date?

    private var progressTimer: Timer?

    public init() {
        // Register HTTP bypass protocol to allow arbitrary HTTP streams (bypasses ATS)
        URLProtocol.registerClass(HTTPBypassProtocol.self)
        setupMemoryPressureObserver()
        setupRemoteCommands()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupMemoryPressureObserver() {
        NotificationCenter.default.addObserver(
            forName: .memoryPressureCritical,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMemoryPressure()
            }
        }
    }

    private func handleMemoryPressure() {
        // Reduce quality to low on critical memory pressure
        if selectedQuality.id != "low" {
            selectedQuality = StreamQualityPreset.low.quality
        }
    }

    // MARK: - Last-channel persistence

    private let lastChannelStore = LastChannelStore()

    /// The last channel URL that was persisted (used by the app to restore on launch).
    public func restoreLastChannel() -> Channel? {
        lastChannelStore.restore()
    }

    // MARK: - Public API

    /// Starts playback of `channel`. Includes debounce guard for UI events.
    public func play(_ channel: Channel) {
        // Guard: same channel, proxy still starting
        if currentChannel?.id == channel.id, isLoadingProxy {
            print("[PlayerCore] play(\(channel.name)) skipped — proxy already starting")
            return
        }

        // Guard: same channel, already playing — nothing to do
        if currentChannel?.id == channel.id, state == .playing {
            print("[PlayerCore] play(\(channel.name)) skipped — already playing")
            return
        }

        // Debounce: ignore play() calls arriving within 500ms of the previous one.
        // Rapid UI events (accidental double-tap, SwiftUI body re-renders) can cascade
        // proxy restarts where each new play() kills the previous proxy before AVPlayer connects.
        let now = Date.now
        if now.timeIntervalSince(lastPlayRequestedAt) < 0.5 {
            print("[PlayerCore] play(\(channel.name)) debounced — \(Int(now.timeIntervalSince(lastPlayRequestedAt) * 1000))ms since last call")
            return
        }
        lastPlayRequestedAt = now

        playInternal(channel)
    }

    /// Internal play — no debounce. Used by playNext/playPrevious/scheduleRetry.
    private func playInternal(_ channel: Channel) {
        // Capture warmup item before clearing state
        let preloadedItem = (warmupChannel?.id == channel.id) ? warmupPlayer?.currentItem : nil
        warmupPlayer = nil
        warmupChannel = nil

        // Persist before switching
        lastChannelStore.save(channel)
        // End previous watch session before switching
        stopProgressTracking()
        endWatchSession()

        // Clean up previous player item and observers
        isLoadingProxy = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        hlsProxy?.stop()
        removeRetryObservers()
        statusObserver?.cancel()
        statusObserver = nil

        currentChannel = channel
        watchStartTime = .now
        state = .loading
        retryCount = 0
        isRetrying = false
        retrySourceItem = nil
        shouldBlockRetry = false
        availableAudioOptions = []
        availableSubtitleOptions = []
        selectedAudioOption = nil
        selectedSubtitleOption = nil
        audioSelectionGroup = nil
        subtitleSelectionGroup = nil

        let url = channel.streamURL
        let ext = url.pathExtension.lowercased()
        print("[PlayerCore] Playing: \(channel.name)")
        print("[PlayerCore]   URL: \(url.absoluteString)")
        print("[PlayerCore]   Extension: \(ext)")

        // VOD types: finite, seekable. Live: indefinite.
        let vodExtensions: Set<String> = ["mkv", "mp4", "avi", "mov", "wmv"]
        isLiveStream = !vodExtensions.contains(ext)

        // Containers that AVPlayer cannot play natively — always route through FFmpeg proxy.
        // mkv: -12847 "Cannot Open"; avi/wmv: no native support; ts/m2ts: -12939 byte-range error.
        let proxyExtensions: Set<String> = ["mkv", "avi", "wmv", "ts", "m2ts"]
        let needsProxy: Bool = proxyExtensions.contains(ext)
            || (channel.contentType == .liveTV && url.path.contains("/live/"))

        if needsProxy {
            guard LocalHLSProxy.isAvailable else {
                print("[PlayerCore] FFmpeg not found")
                state = .error("FFmpeg required. Install: brew install ffmpeg")
                return
            }

            // Don't retry a URL that already failed via FFmpeg this session
            let urlKey = url.absoluteString
            if failedProxyURLs.contains(urlKey) {
                print("[PlayerCore] Skipping known-failed proxy URL: \(url.lastPathComponent)")
                showStreamErrorBanner("Nie można załadować strumienia")
                return
            }

            let proxy = LocalHLSProxy()
            self.hlsProxy = proxy
            isLoadingProxy = true

            print("[PlayerCore]   Using FFmpeg HLS proxy")

            Task { [weak self] in
                do {
                    try await proxy.start(from: url)
                    guard let self, self.currentChannel?.id == channel.id else { return }
                    // isLoadingProxy stays true until AVPlayer confirms readyToPlay or fails.
                    // Clearing it here would open a window where a duplicate play() call could
                    // stop the proxy before AVPlayer has had a chance to connect to it.

                    // Use AVURLAsset with explicit options for local proxy streams.
                    // AVURLAssetPreferPreciseDurationAndTimingKey: false avoids the DRM
                    // key-system probe (FDCP_Limited -12540) that fires on HLS without
                    // a proper EXT-X-STREAM-INF when AVPlayer guesses FairPlay is needed.
                    let proxyAssetOptions: [String: Any] = [
                        AVURLAssetAllowsCellularAccessKey: true,
                        AVURLAssetPreferPreciseDurationAndTimingKey: false,
                        "AVURLAssetHTTPHeaderFieldsKey": ["X-Playback-Session-Id": UUID().uuidString]
                    ]
                    let proxyAsset = AVURLAsset(url: proxy.playlistURL, options: proxyAssetOptions)
                    let item = AVPlayerItem(asset: proxyAsset)
                    item.preferredForwardBufferDuration = channel.contentType == .liveTV ? 4 : 10
                    self.player.replaceCurrentItem(with: item)
                    self.player.play()
                    self.observePlayerItem(item)
                    self.registerRetryObservers(for: item)
                } catch {
                    guard let self, self.currentChannel?.id == channel.id else { return }
                    self.isLoadingProxy = false
                    let errMsg = error.localizedDescription
                    print("[PlayerCore] HLS proxy error: \(errMsg)")

                    // FIX 3: Internal proxy errors caused by rapid channel switching (temp dir
                    // removed or proxy cancelled before FFmpeg started) are not network errors —
                    // retrying would just repeat the cascade. Go idle silently.
                    let isInternalCancel = errMsg.contains("Proxy cancelled") || errMsg.contains("Temp directory removed")
                    if isInternalCancel {
                        print("[PlayerCore] HLS proxy cancelled by channel switch — no retry")
                        self.state = .idle
                        return
                    }

                    // HTTP 400 Bad Request — not recoverable, set error state immediately
                    let is400 = errMsg.contains("400") || errMsg.contains("Bad Request")
                    // HTTP 458 = non-standard IPTV server rejection — retry with alternate extension
                    let is458 = !is400 && (errMsg.contains("458") || errMsg.contains("Server returned 4"))
                    let isTimeout = errMsg.contains("timed out") || errMsg.contains("timeout")
                    if is400 {
                        self.state = .error("HTTP 400 — Nieprawidłowe żądanie")
                        return
                    } else if is458 {
                        await self.retry458WithAlternateExtension(originalURL: url, channel: channel)
                    } else if isTimeout {
                        // Proxy timeout → fall back to direct AVPlayer silently
                        print("[PlayerCore] HLS proxy timeout — falling back to direct AVPlayer")
                        await self.fallbackToDirectPlayer(url: url, channel: channel)
                    } else {
                        // Mark URL as failed to prevent retry loops
                        self.failedProxyURLs.insert(urlKey)
                        self.showStreamErrorBanner("Nie można załadować strumienia")
                    }
                }
            }
            return
        }

        // Direct playback for MP4 and other AVPlayer-compatible formats
        let item: AVPlayerItem
        if let warm = preloadedItem {
            // Use already-buffered item — fast path (< 500ms switch)
            print("[PlayerCore] ⚡ Using preloaded item for: \(channel.name)")
            item = warm
        } else {
            let asset = AVURLAsset(url: url)
            item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 4
        }

        player.replaceCurrentItem(with: item)
        player.play()
        observePlayerItem(item)
        registerRetryObservers(for: item)
    }

    /// Resumes paused playback.
    public func resume() {
        guard case .paused = state else { return }
        player.play()
        state = .playing
        updateNowPlayingInfo()
    }

    /// Pauses playback.
    public func pause() {
        guard case .playing = state else { return }
        player.pause()
        state = .paused
        updateNowPlayingInfo()
    }

    /// Toggles play/pause.
    public func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused:  resume()
        default: break
        }
    }

    /// Stops playback and clears the current channel.
    public func stop() {
        isLoadingProxy = false
        hlsProxy?.stop()
        hlsProxy = nil
        stopProgressTracking()
        endWatchSession()
        removeRetryObservers()
        statusObserver?.cancel()
        statusObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentChannel = nil
        retryCount = 0
        isRetrying = false
        retrySourceItem = nil
        shouldBlockRetry = false
        failedProxyURLs.removeAll()
        warmupPlayer = nil
        warmupChannel = nil
        availableAudioOptions = []
        availableSubtitleOptions = []
        selectedAudioOption = nil
        selectedSubtitleOption = nil
        audioSelectionGroup = nil
        subtitleSelectionGroup = nil
        state = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Toggles mute.
    public func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    /// Sets volume (0.0 – 1.0).
    public func setVolume(_ value: Float) {
        volume = max(0, min(1, value))
        player.volume = volume
    }

    // MARK: - Channel navigation

    /// Plays the next channel in `channelList`.
    public func playNext() {
        guard let current = currentChannel,
              let idx = channelList.firstIndex(of: current),
              idx + 1 < channelList.count else { return }
        retryCount = 0
        playInternal(channelList[idx + 1])
    }

    /// Plays the previous channel in `channelList`.
    public func playPrevious() {
        guard let current = currentChannel,
              let idx = channelList.firstIndex(of: current),
              idx > 0 else { return }
        retryCount = 0
        playInternal(channelList[idx - 1])
    }

    /// Seeks forward or backward by `seconds` (positive = forward, negative = backward).
    /// No-op for live streams.
    public func seek(by seconds: Double) {
        guard !isLiveStream else { return }
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        let target = max(0, current + seconds)
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Adjusts volume by delta (-1.0 to +1.0), clamped to 0–1.
    /// Used by scroll wheel gesture over the player.
    public func adjustVolume(delta: Float) {
        setVolume(volume + delta)
    }

    /// Called by the AVPlayerView coordinator when PiP state changes.
    public func setPiPActive(_ active: Bool) {
        isPiPActive = active
    }

    /// Posts a notification that VideoPlayerLayer's coordinator intercepts to call startPictureInPicture().
    public func startPiP() {
        NotificationCenter.default.post(name: .pipStartRequested, object: nil)
    }

    /// Selects the given audio track on the current player item.
    public func selectAudioOption(_ option: AVMediaSelectionOption) {
        guard let item = player.currentItem, let group = audioSelectionGroup else { return }
        item.select(option, in: group)
        selectedAudioOption = option
    }

    /// Selects the given subtitle track, or nil to disable subtitles.
    public func selectSubtitleOption(_ option: AVMediaSelectionOption?) {
        guard let item = player.currentItem, let group = subtitleSelectionGroup else { return }
        item.select(option, in: group)
        selectedSubtitleOption = option
    }

    // MARK: - Auto-retry

    /// Schedules a retry with exponential backoff (2s, 4s, 6s).
    /// On retry, increases the forward buffer to help with weak-signal streams.
    /// `item` identifies the failing item — duplicate calls for the same item are ignored.
    private func scheduleRetry(for item: AVPlayerItem) {
        guard !shouldBlockRetry else {
            showStreamErrorBanner("Nie można załadować strumienia")
            return
        }
        // De-duplicate: if we're already retrying because of this exact item, skip.
        guard retrySourceItem !== item else { return }
        guard !isRetrying else { return }
        guard retryCount < maxRetries, let channel = currentChannel else {
            isRetrying = false
            retrySourceItem = nil
            showStreamErrorBanner("Nie można załadować strumienia")
            return
        }
        isRetrying = true
        retrySourceItem = item
        retryCount += 1
        let delay = Double(retryCount) * 2.0
        state = .loading

        // Increase buffer on retry — weak signal likely
        if let currentItem = player.currentItem {
            BufferingConfig.applyAdaptive(to: currentItem)
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            // Only retry if we're still on the same channel
            guard self.currentChannel?.id == channel.id else {
                self.isRetrying = false
                self.retrySourceItem = nil
                return
            }
            self.isRetrying = false
            self.retrySourceItem = nil
            self.removeRetryObservers()
            self.playInternal(channel)
        }
    }

    private func registerRetryObservers(for item: AVPlayerItem) {
        let center = NotificationCenter.default

        failedObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let nsErr = err as NSError?
            print("[PlayerCore] ⚠️ Failed to play to end: \(err?.localizedDescription ?? "unknown")")
            Task { @MainActor [weak self] in
                guard let self,
                      let item,
                      item === self.player.currentItem else { return }
                // -16845 = CoreMedia MKV "Cannot Open" — try .ts extension before giving up
                let httpCode = nsErr?.code ?? 0
                if nsErr?.code == -16845 {
                    print("[PlayerCore] 🔄 Error -16845 (Cannot Open) — retrying with .ts extension")
                    if let ch = self.currentChannel {
                        let tsURL = ch.streamURL.deletingPathExtension().appendingPathExtension("ts")
                        await self.fallbackToDirectPlayer(url: tsURL, channel: ch)
                    }
                    return
                }
                if nsErr?.domain == "CoreMediaErrorDomain" || (400...499).contains(httpCode) {
                    print("[PlayerCore] 🚫 Error \(nsErr?.domain ?? "?") \(httpCode) — blocking retry")
                    self.shouldBlockRetry = true
                    if httpCode == 458 {
                        self.showStreamErrorBanner("Nie można załadować strumienia")
                        return
                    }
                }
                self.scheduleRetry(for: item)
            }
        }

        stallObserver = center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            Task { @MainActor [weak self] in
                guard let self,
                      let item,
                      item === self.player.currentItem else { return }
                guard !self.isLoadingProxy else { return }
                // If we have an HLS proxy, check if it's still alive before retrying.
                // A dead proxy means we must restart it and replace the AVPlayerItem —
                // simply retrying the old URL (on the old port) will get Connection refused.
                if let proxy = self.hlsProxy {
                    if proxy.isRunning {
                        // Proxy alive — seek to current position to un-stall
                        let pos = self.player.currentTime()
                        await self.player.seek(to: pos)
                        self.player.play()
                    } else {
                        // Proxy died — restart proxy and replace AVPlayerItem with new URL
                        await self.restartProxyAndReplaceItem()
                    }
                } else {
                    self.scheduleRetry(for: item)
                }
            }
        }
    }

    private func removeRetryObservers() {
        let center = NotificationCenter.default
        if let obs = stallObserver { center.removeObserver(obs); stallObserver = nil }
        if let obs = failedObserver { center.removeObserver(obs); failedObserver = nil }
    }

    /// Restarts the HLS proxy (which binds a new port) and replaces the AVPlayerItem
    /// so AVPlayer uses the new URL. Prevents Connection refused on the old port.
    private func restartProxyAndReplaceItem() async {
        guard let channel = currentChannel,
              let proxy = hlsProxy,
              let sourceURL = channel.streamURL as URL? else { return }

        guard retryCount < maxRetries else {
            showStreamErrorBanner("Nie można załadować strumienia")
            return
        }
        retryCount += 1
        state = .loading
        print("[PlayerCore] Proxy died — restarting (attempt \(retryCount))")

        // Wait 2s before restarting to let the OS release the port
        try? await Task.sleep(for: .seconds(2))
        guard currentChannel?.id == channel.id else { return }

        removeRetryObservers()
        statusObserver?.cancel()
        statusObserver = nil

        do {
            try await proxy.start(from: sourceURL)
            guard currentChannel?.id == channel.id else { return }

            let proxyAssetOptions: [String: Any] = [
                AVURLAssetAllowsCellularAccessKey: true,
                AVURLAssetPreferPreciseDurationAndTimingKey: false,
                "AVURLAssetHTTPHeaderFieldsKey": ["X-Playback-Session-Id": UUID().uuidString]
            ]
            let proxyAsset = AVURLAsset(url: proxy.playlistURL, options: proxyAssetOptions)
            let newItem = AVPlayerItem(asset: proxyAsset)
            newItem.preferredForwardBufferDuration = isLiveStream ? 4 : 10
            player.replaceCurrentItem(with: newItem)
            player.play()
            observePlayerItem(newItem)
            registerRetryObservers(for: newItem)
            print("[PlayerCore] Proxy restarted, new URL: \(proxy.playlistURL)")
        } catch {
            guard currentChannel?.id == channel.id else { return }
            print("[PlayerCore] Proxy restart failed: \(error.localizedDescription)")
            showStreamErrorBanner("Nie można załadować strumienia")
        }
    }

    // MARK: - 458 retry helpers

    /// When a proxied stream returns HTTP 458 for (e.g.) a .mkv URL, try the same stream ID
    /// with .ts extension via FFmpeg proxy, then .mp4, then fall back to direct AVPlayer.
    private func retry458WithAlternateExtension(originalURL: URL, channel: Channel) async {
        let extensions458: [String] = ["ts", "mp4"]
        for ext in extensions458 {
            guard currentChannel?.id == channel.id else { return }
            let altURL = originalURL.deletingPathExtension().appendingPathExtension(ext)
            print("[PlayerCore] 458 retry with .\(ext) extension: \(altURL.absoluteString)")

            // Proxy-eligible extensions
            let proxyExts: Set<String> = ["ts", "mkv", "avi", "wmv", "m2ts"]
            if proxyExts.contains(ext) {
                let proxy = LocalHLSProxy()
                self.hlsProxy = proxy
                do {
                    try await proxy.start(from: altURL)
                    guard currentChannel?.id == channel.id else { return }
                    let opts: [String: Any] = [
                        AVURLAssetAllowsCellularAccessKey: true,
                        AVURLAssetPreferPreciseDurationAndTimingKey: false,
                        "AVURLAssetHTTPHeaderFieldsKey": ["X-Playback-Session-Id": UUID().uuidString]
                    ]
                    let asset = AVURLAsset(url: proxy.playlistURL, options: opts)
                    let item = AVPlayerItem(asset: asset)
                    item.preferredForwardBufferDuration = 10
                    player.replaceCurrentItem(with: item)
                    player.play()
                    observePlayerItem(item)
                    registerRetryObservers(for: item)
                    return // success
                } catch {
                    let msg = error.localizedDescription
                    let again458 = msg.contains("458") || msg.contains("Server returned 4")
                    if !again458 {
                        self.state = .error(msg)
                        return
                    }
                    // another 458 — continue to next extension
                    print("[PlayerCore] 458 again for .\(ext), trying next")
                }
            } else {
                // mp4 — try direct AVPlayer (AVPlayer supports mp4)
                let asset = AVURLAsset(url: altURL)
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 10
                player.replaceCurrentItem(with: item)
                player.play()
                observePlayerItem(item)
                shouldBlockRetry = true // 4xx chain — don't auto-retry
                registerRetryObservers(for: item)
                return
            }
        }

        // All extension retries exhausted — try direct AVPlayer with original URL as last resort
        guard currentChannel?.id == channel.id else { return }
        print("[PlayerCore] 458 all retries failed — falling back to direct AVPlayer")
        let asset = AVURLAsset(url: originalURL)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        player.replaceCurrentItem(with: item)
        player.play()
        observePlayerItem(item)
        shouldBlockRetry = true
        registerRetryObservers(for: item)
    }

    // MARK: - Banner helper

    /// Clears the stream error banner immediately.
    public func clearStreamErrorBanner() {
        streamErrorBanner = nil
    }

    /// Shows a transient error banner and returns player to idle after 5s.
    private func showStreamErrorBanner(_ message: String) {
        print("[PlayerCore] 🔔 Banner: \(message)")
        streamErrorBanner = message
        state = .idle
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            if self.streamErrorBanner == message {
                self.streamErrorBanner = nil
            }
        }
    }

    /// Falls back to direct AVPlayer playback (no FFmpeg proxy) for the given URL.
    private func fallbackToDirectPlayer(url: URL, channel: Channel) async {
        guard currentChannel?.id == channel.id else { return }
        print("[PlayerCore] Direct AVPlayer fallback: \(url.lastPathComponent)")
        removeRetryObservers()
        statusObserver?.cancel()
        statusObserver = nil
        hlsProxy?.stop()
        hlsProxy = nil
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4
        player.replaceCurrentItem(with: item)
        player.play()
        observePlayerItem(item)
        registerRetryObservers(for: item)
    }

    // MARK: - Warmup preload

    @MainActor
    private func warmupNextChannel() {
        guard !channelList.isEmpty,
              let current = currentChannel,
              let idx = channelList.firstIndex(where: { $0.id == current.id }),
              channelList.count > 1 else { return }
        let nextIdx = (idx + 1) % channelList.count
        let next = channelList[nextIdx]
        guard next.id != warmupChannel?.id else { return }
        warmupChannel = next
        let item = AVPlayerItem(url: next.streamURL)
        item.preferredForwardBufferDuration = 10
        warmupPlayer = AVPlayer(playerItem: item)
        warmupPlayer?.isMuted = true
        warmupPlayer?.playImmediately(atRate: 0)
        print("[PlayerCore] 🔄 Warming up: \(next.name)")
    }

    // MARK: - Private

    private func loadMediaTracks(from item: AVPlayerItem) async {
        let asset = item.asset
        do {
            if let group = try await asset.loadMediaSelectionGroup(for: .audible) {
                audioSelectionGroup = group
                availableAudioOptions = group.options
                selectedAudioOption = item.currentMediaSelection.selectedMediaOption(in: group)
            }
            if let group = try await asset.loadMediaSelectionGroup(for: .legible) {
                subtitleSelectionGroup = group
                availableSubtitleOptions = group.options
                selectedSubtitleOption = item.currentMediaSelection.selectedMediaOption(in: group)
            }
        } catch {
            print("[PlayerCore] Failed to load media tracks: \(error)")
        }
    }

    private func startProgressTracking(channel: Channel) {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = self.player.currentTime().seconds
            let rawDuration = self.player.currentItem?.duration.seconds ?? 0
            let duration = rawDuration.isNaN || rawDuration.isInfinite ? 0 : rawDuration
            if current > 0 {
                Task { @MainActor [weak self] in
                    self?.onProgressUpdate?(channel.id, current, duration)
                }
            }
        }
    }

    private func stopProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Ends the current watch session and fires the callback.
    private func endWatchSession() {
        guard let channel = currentChannel, let start = watchStartTime else { return }
        let duration = Int(Date.now.timeIntervalSince(start))
        if duration > 3 { // ignore accidental taps (< 3 seconds)
            onWatchSessionEnd?(channel, start, duration)
        }
        watchStartTime = nil
    }

    // MARK: - Now Playing / Remote Commands

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.stop() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.playPrevious() }
            return .success
        }
        // Disable seek/scrub commands — live streams don't support them
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
    }

    private func updateNowPlayingInfo() {
        guard let channel = currentChannel else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.name,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: isLiveStream,
        ]
        if !isLiveStream {
            let elapsed = player.currentTime().seconds
            if elapsed.isFinite, elapsed >= 0 {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
            }
            let duration = player.currentItem?.duration.seconds ?? 0
            if duration.isFinite, duration > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let logoURL = channel.logoURL {
            Task { [weak self] in await self?.loadArtwork(from: logoURL) }
        }
    }

    private func loadArtwork(from url: URL) async {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        #if os(macOS)
        guard let image = NSImage(data: data) else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #else
        guard let image = UIImage(data: data) else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #endif
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - observePlayerItem

    private func observePlayerItem(_ item: AVPlayerItem) {
        // Cancel previous observer to prevent memory leaks
        statusObserver?.cancel()
        statusObserver = nil

        statusObserver = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak item] status in
                guard let self, let item else { return }
                switch status {
                case .readyToPlay:
                    // Proxy (if any) is confirmed usable by AVPlayer — safe to allow new play() calls.
                    self.isLoadingProxy = false
                    print("[PlayerCore] ✅ readyToPlay")
                    self.retryCount = 0
                    self.retrySourceItem = nil
                    self.state = .playing
                    // Determine live vs VOD from actual item duration
                    let dur = item.duration
                    if dur.isIndefinite || dur == .zero {
                        self.isLiveStream = true
                    } else if dur.isNumeric && dur.seconds > 0 {
                        self.isLiveStream = false
                    }
                    self.updateNowPlayingInfo()
                    // Reset buffer to normal after successful recovery
                    BufferingConfig.resetToNormal(for: item)
                    // Start progress tracking for Continue Watching
                    if let ch = self.currentChannel {
                        self.startProgressTracking(channel: ch)
                    }
                    // Load available audio and subtitle tracks
                    Task { [weak self] in
                        guard let self else { return }
                        guard let item = self.player.currentItem else { return }
                        await self.loadMediaTracks(from: item)
                    }
                    // Preload next channel 2s after playback starts
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        self?.warmupNextChannel()
                    }
                case .failed:
                    self.isLoadingProxy = false
                    let err = item.error?.localizedDescription ?? "unknown"
                    print("[PlayerCore] ❌ FAILED: \(err)")
                    if let underlying = (item.error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? NSError {
                        print("[PlayerCore]   Underlying: \(underlying.domain) \(underlying.code) \(underlying.localizedDescription)")
                        // Block retry for any 4xx HTTP error (client errors — won't fix with retry)
                        // Common: 400 Bad Request, 403 Forbidden, 404 Not Found, 458 (IPTV rate limit)
                        let httpCode = underlying.code
                        if (400...499).contains(httpCode) || underlying.domain == "CoreMediaErrorDomain" {
                            print("[PlayerCore] 🚫 HTTP \(httpCode) (\(underlying.domain)) — blocking retry, not recoverable")
                            self.shouldBlockRetry = true
                        }
                    }
                    // Schedule retry — scheduleRetry will show banner after maxRetries
                    self.scheduleRetry(for: item)
                case .unknown:
                    print("[PlayerCore] ⏳ status unknown (waiting...)")
                @unknown default:
                    break
                }
            }
    }

}

public extension Notification.Name {
    static let pipStartRequested = Notification.Name("AetherPiPStartRequested")
}
