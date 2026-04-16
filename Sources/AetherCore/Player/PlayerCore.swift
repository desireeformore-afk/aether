import AVFoundation
import Combine
import Foundation

/// Playback state of `PlayerCore`.
public enum PlayerState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case error(String)
}

/// A `@MainActor` wrapper around `AVPlayer` for IPTV stream playback.
/// Supports play/pause/stop/mute/volume, PiP delegation, channel navigation,
/// and watch session tracking via `onWatchSessionEnd` callback.
@MainActor
public final class PlayerCore: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var state: PlayerState = .idle
    @Published public private(set) var currentChannel: Channel?
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var volume: Float = 1.0
    @Published public private(set) var isPiPActive: Bool = false
    @Published public var selectedQuality: StreamQuality = StreamQuality.auto {
        didSet { StreamQualityService().apply(selectedQuality, to: player) }
    }

    /// Available quality presets.
    public let qualityPresets: [StreamQuality] = StreamQualityPreset.allCases.map { $0.quality }

    // MARK: - Channel navigation support

    /// The ordered list of channels the user is currently browsing.
    /// Set by `ChannelListView` when a playlist is loaded.
    public var channelList: [Channel] = []

    // MARK: - Watch history callback

    /// Called when a watch session ends (channel switched or stopped).
    /// Parameters: (channel, startDate, durationSeconds)
    public var onWatchSessionEnd: ((Channel, Date, Int) -> Void)?

    // MARK: - Internal

    public let player: AVPlayer = AVPlayer()

    private var statusObserver: AnyCancellable?

    /// Tracks when the current channel started playing.
    private var watchStartTime: Date?

    public init() {}

    // MARK: - Public API

    /// Starts playback of `channel`.
    public func play(_ channel: Channel) {
        // End previous watch session before switching
        endWatchSession()

        currentChannel = channel
        watchStartTime = .now
        state = .loading

        let item = AVPlayerItem(url: channel.streamURL)
        item.preferredPeakBitRate = selectedQuality.peakBitRate
        player.replaceCurrentItem(with: item)
        player.play()
        observePlayerItem(item)
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
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentChannel = nil
        state = .idle
        statusObserver = nil
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
        play(channelList[idx + 1])
    }

    /// Plays the previous channel in `channelList`.
    public func playPrevious() {
        guard let current = currentChannel,
              let idx = channelList.firstIndex(of: current),
              idx > 0 else { return }
        play(channelList[idx - 1])
    }

    // MARK: - PiP state callback (set by VideoPlayerLayer coordinator)

    /// Called by the AVPlayerView coordinator when PiP state changes.
    public func setPiPActive(_ active: Bool) {
        isPiPActive = active
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
        statusObserver = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.state = .playing
                case .failed:
                    let msg = item.error?.localizedDescription ?? "Unknown error"
                    self.state = .error(msg)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
    }
}
