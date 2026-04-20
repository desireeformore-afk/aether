@preconcurrency import AVFoundation
@preconcurrency import Combine
import Foundation

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

    /// Current playback time in seconds.
    public var currentTime: TimeInterval {
        player.currentTime().seconds
    }

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

    // MARK: - Watch history callback

    /// Called when a watch session ends (channel switched or stopped).
    /// Parameters: (channel, startDate, durationSeconds)
    public var onWatchSessionEnd: ((Channel, Date, Int) -> Void)?

    // MARK: - Internal

    /// The underlying AVPlayer instance.
    public let player: AVPlayer = AVPlayer()

    private var statusObserver: AnyCancellable?
    private var stallObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var isRetrying: Bool = false
    /// The AVPlayerItem that triggered the current pending retry (prevents duplicate retries
    /// when both .status == .failed and AVPlayerItemFailedToPlayToEndTime fire for the same item).
    private weak var retrySourceItem: AVPlayerItem?

    /// Blocks retry when HTTP 400 error is detected.
    private var shouldBlockRetry: Bool = false

    /// FFmpeg HLS proxy — remuxes TS/MKV to local HLS segments for AVPlayer
    private var hlsProxy: LocalHLSProxy?

    /// Tracks when the current channel started playing.
    private var watchStartTime: Date?

    public init() {
        // Register HTTP bypass protocol to allow arbitrary HTTP streams (bypasses ATS)
        URLProtocol.registerClass(HTTPBypassProtocol.self)
        setupMemoryPressureObserver()
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
            Task { @MainActor in
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

    /// Starts playback of `channel`.
    public func play(_ channel: Channel) {
        // Persist before switching
        lastChannelStore.save(channel)
        // End previous watch session before switching
        endWatchSession()

        // Clean up previous player item and observers
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

        let url = channel.streamURL
        let ext = url.pathExtension.lowercased()
        print("[PlayerCore] Playing: \(channel.name)")
        print("[PlayerCore]   URL: \(url.absoluteString)")
        print("[PlayerCore]   Extension: \(ext)")

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

            let proxy = LocalHLSProxy()
            self.hlsProxy = proxy

            print("[PlayerCore]   Using FFmpeg HLS proxy")

            Task { [weak self] in
                do {
                    try await proxy.start(from: url)
                    guard let self, self.currentChannel?.id == channel.id else { return }

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
                    let errMsg = error.localizedDescription
                    print("[PlayerCore] HLS proxy error: \(errMsg)")

                    // HTTP 458 = non-standard IPTV server rejection — FFmpeg can't handle it.
                    // Fall back to direct AVPlayer; some servers accept it where FFmpeg is blocked.
                    let is458 = errMsg.contains("458") || errMsg.contains("Server returned 4")
                    if is458 {
                        print("[PlayerCore] HTTP 458 detected — falling back to direct AVPlayer")
                        let asset = AVURLAsset(url: url)
                        let item = AVPlayerItem(asset: asset)
                        item.preferredForwardBufferDuration = 4
                        self.player.replaceCurrentItem(with: item)
                        self.player.play()
                        self.observePlayerItem(item)
                        self.registerRetryObservers(for: item)
                        // Mark 458 so that if AVPlayer also fails we don't retry
                        self.shouldBlockRetry = true
                    } else {
                        self.state = .error(errMsg)
                    }
                }
            }
            return
        }

        // Direct playback for MP4 and other AVPlayer-compatible formats
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4

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
    }

    /// Pauses playback.
    public func pause() {
        guard case .playing = state else { return }
        player.pause()
        state = .paused
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
        state = .idle
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
        play(channelList[idx + 1])
    }

    /// Plays the previous channel in `channelList`.
    public func playPrevious() {
        guard let current = currentChannel,
              let idx = channelList.firstIndex(of: current),
              idx > 0 else { return }
        retryCount = 0
        play(channelList[idx - 1])
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

    // MARK: - Auto-retry

    /// Schedules a retry with exponential backoff (2s, 4s, 6s).
    /// On retry, increases the forward buffer to help with weak-signal streams.
    /// `item` identifies the failing item — duplicate calls for the same item are ignored.
    private func scheduleRetry(for item: AVPlayerItem) {
        guard !shouldBlockRetry else {
            state = .error("Stream rejected by server (client error — not retrying)")
            return
        }
        // De-duplicate: if we're already retrying because of this exact item, skip.
        guard retrySourceItem !== item else { return }
        guard !isRetrying else { return }
        guard retryCount < maxRetries, let channel = currentChannel else {
            isRetrying = false
            retrySourceItem = nil
            state = .error("Stream unavailable after \(maxRetries) retries")
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

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            // Only retry if we're still on the same channel
            guard self.currentChannel?.id == channel.id else {
                self.isRetrying = false
                self.retrySourceItem = nil
                return
            }
            self.isRetrying = false
            self.retrySourceItem = nil
            self.removeRetryObservers()
            self.play(channel)
        }
    }

    private func registerRetryObservers(for item: AVPlayerItem) {
        let center = NotificationCenter.default

        // Failed to play to end — bind to the specific item to avoid cross-item noise
        failedObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
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
                // -16845 = CoreMedia HTTP 458 (IPTV rate limit / server refusal) — not retryable
                // Also block for any underlying 4xx HTTP error exposed via NSError code
                let httpCode = nsErr?.code ?? 0
                if nsErr?.code == -16845 || nsErr?.domain == "CoreMediaErrorDomain"
                    || (400...499).contains(httpCode) {
                    print("[PlayerCore] 🚫 Error \(nsErr?.domain ?? "?") \(httpCode) — blocking retry")
                    self.shouldBlockRetry = true
                    // Provide a user-friendly message for 458 specifically
                    if httpCode == 458 || nsErr?.code == -16845 {
                        self.state = .error("Stream niedostępny (HTTP 458 — serwer odrzucił połączenie)")
                        return
                    }
                }
                self.scheduleRetry(for: item)
            }
        }

        // Playback stalled — bind to the specific item to avoid cross-item noise
        stallObserver = center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let item = notification.object as? AVPlayerItem
            Task { @MainActor [weak self] in
                guard let self,
                      let item,
                      item === self.player.currentItem else { return }
                self.scheduleRetry(for: item)
            }
        }
    }

    private func removeRetryObservers() {
        let center = NotificationCenter.default
        if let obs = stallObserver { center.removeObserver(obs); stallObserver = nil }
        if let obs = failedObserver { center.removeObserver(obs); failedObserver = nil }
    }

    // MARK: - Private

    /// Ends the current watch session and fires the callback.
    private func endWatchSession() {
        guard let channel = currentChannel, let start = watchStartTime else { return }
        let duration = Int(Date.now.timeIntervalSince(start))
        if duration > 3 { // ignore accidental taps (< 3 seconds)
            onWatchSessionEnd?(channel, start, duration)
        }
        watchStartTime = nil
    }

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
                    print("[PlayerCore] ✅ readyToPlay")
                    self.retryCount = 0
                    self.retrySourceItem = nil
                    self.state = .playing
                    // Reset buffer to normal after successful recovery
                    BufferingConfig.resetToNormal(for: item)
                case .failed:
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
                    self.state = .error(err)
                    // Don't auto-retry — show error to user for debugging
                case .unknown:
                    print("[PlayerCore] ⏳ status unknown (waiting...)")
                @unknown default:
                    break
                }
            }
    }

}
