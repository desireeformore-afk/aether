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
@MainActor
public final class PlayerCore: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var state: PlayerState = .idle
    @Published public private(set) var currentChannel: Channel?
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var volume: Float = 1.0

    // MARK: - Internal

    public let player: AVPlayer = AVPlayer()

    private var statusObserver: AnyCancellable?
    private var errorObserver: AnyCancellable?

    public init() {
        observePlayer()
    }

    // MARK: - Public API

    /// Starts playback of `channel`.
    public func play(_ channel: Channel) {
        currentChannel = channel
        state = .loading

        let item = AVPlayerItem(url: channel.streamURL)
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

    /// Stops playback and clears the current channel.
    public func stop() {
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

    // MARK: - Private

    private func observePlayer() {
        // Nothing global needed for now; item-level observation handles state.
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
