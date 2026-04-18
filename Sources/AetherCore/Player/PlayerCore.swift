import AVFoundation
import Combine
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
public final class PlayerCore: ObservableObject {

    // MARK: - Published state

    /// Current playback state.
    @Published public private(set) var state: PlayerState = .idle

    /// Currently playing channel, if any.
    @Published public private(set) var currentChannel: Channel?

    /// Whether audio is muted.
    @Published public private(set) var isMuted: Bool = false

    /// Audio volume (0.0 to 1.0).
    @Published public private(set) var volume: Float = 1.0

    /// Whether Picture-in-Picture is active.
    @Published public private(set) var isPiPActive: Bool = false

    /// Current playback time in seconds.
    public var currentTime: TimeInterval {
        player.currentTime().seconds
    }

    /// Whether playback is currently active.
    public var isPlaying: Bool {
        state == .playing
    }

    /// Selected stream quality preset.
    @Published public var selectedQuality: StreamQuality = StreamQuality.auto {
        didSet { StreamQualityService().apply(selectedQuality, to: player) }
    }

    /// Current retry attempt count (0 = first play, >0 = retrying).
    @Published public private(set) var retryCount: Int = 0

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

    /// Tracks when the current channel started playing.
    private var watchStartTime: Date?

    public init() {
        // Register HTTP bypass protocol to allow arbitrary HTTP streams (bypasses ATS)
        URLProtocol.registerClass(HTTPBypassProtocol.self)
        setupMemoryPressureObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        statusObserver?.cancel()
        statusObserver = nil
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
        removeRetryObservers()
        statusObserver?.cancel()
        statusObserver = nil

        currentChannel = channel
        watchStartTime = .now
        state = .loading
        retryCount = 0
        isRetrying = false
        retrySourceItem = nil

        // Build URLRequest with HTTP/1.1 forced — IPTV streams don't support QUIC/HTTP3
        var request = URLRequest(url: channel.streamURL)
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let asset = AVURLAsset(
            url: channel.streamURL,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": request.allHTTPHeaderFields ?? [:],
                AVURLAssetPreferPreciseDurationAndTimingKey: false,
                // Disable QUIC — forces TCP/HTTP which IPTV servers actually support
                "AVURLAssetAllowsCellularAccessKey": true,
                // Use our custom URLProtocol for HTTP bypass
                "AVURLAssetURLSessionClientKey": URLProtocol.self,
            ]
        )

        let item = AVPlayerItem(asset: asset)
        item.preferredPeakBitRate = selectedQuality.peakBitRate

        // Apply buffering settings
        BufferingConfig.apply(to: item)
        BufferingConfig.apply(to: player)

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

    // MARK: - PiP state callback (set by VideoPlayerLayer coordinator)

    /// Called by the AVPlayerView coordinator when PiP state changes.
    public func setPiPActive(_ active: Bool) {
        isPiPActive = active
    }

    // MARK: - Auto-retry

    /// Schedules a retry with exponential backoff (2s, 4s, 6s).
    /// `item` identifies the failing item — duplicate calls for the same item are ignored.
    private func scheduleRetry(for item: AVPlayerItem) {
        // De-duplicate: if we're already retrying because of this exact item, skip.
        guard retrySourceItem !== item else { return }
        guard !isRetrying else { return }
        guard retryCount < maxRetries, let channel = currentChannel else {
            state = .error("Stream unavailable after \(maxRetries) retries")
            return
        }
        isRetrying = true
        retrySourceItem = item
        retryCount += 1
        let delay = Double(retryCount) * 2.0
        state = .loading
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

        // Failed to play to end
        failedObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let item = notification.object as? AVPlayerItem,
                      item === self.player.currentItem else { return }
                self.scheduleRetry(for: item)
            }
        }

        // Playback stalled
        stallObserver = center.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let item = notification.object as? AVPlayerItem,
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
                    self.retryCount = 0
                    self.retrySourceItem = nil
                    self.state = .playing
                case .failed:
                    self.state = .loading  // Show user we're retrying
                    self.scheduleRetry(for: item)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
    }

}
