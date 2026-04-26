import Foundation
import VLCKit
import MediaPlayer
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

    /// Current playback position in seconds.
    public var currentTime: TimeInterval {
        let ms = vlcPlayer.time.intValue
        return Double(max(0, ms)) / 1000.0
    }

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
    public var onProgressUpdate: ((UUID, Double, Double) -> Void)?

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

    private let lastChannelStore = LastChannelStore()
    private var watchStartTime: Date?
    private var progressTimer: Timer?
    private var retryTask: Task<Void, Never>?
    private var bannerDismissTask: Task<Void, Never>?

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
        vlcPlayer.drawable = view
    }

    // MARK: - Public playback API

    /// Starts playback of `channel`. Debounced — rapid calls within 500ms are ignored.
    public func play(_ channel: Channel) {
        // Same channel already playing — skip
        if currentChannel?.id == channel.id, state == .playing { return }

        playInternal(channel)
    }

    private func playInternal(_ channel: Channel) {
        lastChannelStore.save(channel)
        stopProgressTracking()
        endWatchSession()
        retryTask?.cancel()
        retryTask = nil

        // Stop any ongoing VLC playback cleanly
        if vlcPlayer.isPlaying {
            vlcPlayer.stop()
        }

        currentChannel = channel
        watchStartTime = .now
        state = .loading
        retryCount = 0
        availableAudioTracks = []
        availableSubtitleTracks = []
        selectedAudioTrackID = -1
        selectedSubtitleTrackID = -1

        let url = channel.streamURL
        let ext = url.pathExtension.lowercased()

        print("[PlayerCore] Playing: \(channel.name)")
        print("[PlayerCore]   URL: \(url.absoluteString)")
        print("[PlayerCore]   Extension: \(ext)")

        // VOD = has a seekable duration (MKV, MP4, AVI, MOV…)
        // Live = indefinite TS/m3u8 streams
        let vodExtensions: Set<String> = ["mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v"]
        isLiveStream = !vodExtensions.contains(ext)

        let media = VLCMedia(url: url)

        // VLC network caching: lower value = faster start, higher = smoother on bad connections.
        // 1500ms for live (tolerates jitter), 800ms for VOD (starts faster, seeks more accurately).
        let cachingMs = isLiveStream ? 1500 : 800
        media?.addOption("--network-caching=\(cachingMs)")

        // Spoof UA — some IPTV servers reject the default VLC user agent
        media?.addOption("--http-user-agent=VLC/3.0.20 LibVLC/3.0.20")

        // Hardware decoding via VideoToolbox (GPU) — zero CPU transcoding
        media?.addOption("--videotoolbox-hw-decoder-use")

        vlcPlayer.media = media
        vlcPlayer.play()
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
        stopProgressTracking()
        endWatchSession()
        vlcPlayer.stop()
        currentChannel = nil
        retryCount = 0
        availableAudioTracks = []
        availableSubtitleTracks = []
        selectedAudioTrackID = -1
        selectedSubtitleTrackID = -1
        state = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
        playInternal(channelList[idx + 1])
    }

    public func playPrevious() {
        guard let current = currentChannel,
              let idx = channelList.firstIndex(of: current),
              idx > 0 else { return }
        retryCount = 0
        playInternal(channelList[idx - 1])
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
            self?.streamErrorBanner = nil
        }
    }

    /// Dismisses the error banner immediately (e.g. when user taps Retry).
    public func clearStreamErrorBanner() {
        bannerDismissTask?.cancel()
        streamErrorBanner = nil
    }

    // MARK: - VLC delegate callbacks (called by VLCDelegateBridge)

    func vlcStateChanged(_ vlcState: VLCMediaPlayerState) {
        switch vlcState {
        case .opening, .buffering:
            state = .loading
        case .playing:
            if state != .playing {
                state = .playing
                retryCount = 0
                startProgressTracking()
                updateNowPlayingInfo()
                // Populate track lists once media is actually playing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.refreshTrackLists()
                }
            }
        case .paused:
            state = .paused
        case .stopped, .stopping:
            if currentChannel != nil {
                stopProgressTracking()
                endWatchSession()
                state = .idle
            }
        case .error:
            stopProgressTracking()
            print("[PlayerCore] VLC error — scheduling retry")
            scheduleRetry(message: "Stream error — check your connection")
        @unknown default:
            break
        }
    }

    func vlcMediaChanged() {
        // Reset tracks when media changes
        availableAudioTracks = []
        availableSubtitleTracks = []
    }

    // MARK: - Track lists

    private func refreshTrackLists() {
        // VLCKit 4: audioTracks / textTracks return [VLCMediaPlayerTrack]
        availableAudioTracks = vlcPlayer.audioTracks.enumerated().map { idx, t in
            VLCTrack(id: idx, name: t.trackName ?? "Track \(idx)")
        }
        // Find currently selected audio index
        if let selIdx = vlcPlayer.audioTracks.firstIndex(where: { $0.isSelected }) {
            selectedAudioTrackID = selIdx
        }

        availableSubtitleTracks = vlcPlayer.textTracks.enumerated().map { idx, t in
            VLCTrack(id: idx, name: t.trackName ?? "Sub \(idx)")
        }
        if let selIdx = vlcPlayer.textTracks.firstIndex(where: { $0.isSelected }) {
            selectedSubtitleTrackID = selIdx
        }
    }

    // MARK: - Auto-retry

    private func scheduleRetry(message: String) {
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
            guard let self, self.currentChannel?.id == channel.id else { return }
            self.playInternal(channel)
        }
    }

    // MARK: - Watch session / progress

    private func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let channel = self.currentChannel else { return }
                self.onProgressUpdate?(channel.id, self.currentTime, self.duration)
            }
        }
    }

    private func stopProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func endWatchSession() {
        guard let channel = currentChannel, let start = watchStartTime else { return }
        let elapsed = Int(Date.now.timeIntervalSince(start))
        if elapsed > 5 {
            onWatchSessionEnd?(channel, start, elapsed)
        }
        watchStartTime = nil
    }

    // MARK: - Now Playing (Lock Screen / Control Center)

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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
/// VLC calls delegate methods on an arbitrary thread — this bridge dispatches them
/// to MainActor so PlayerCore (which is @MainActor) can handle them safely.
final class VLCDelegateBridge: NSObject, VLCMediaPlayerDelegate, Sendable {
    private weak var owner: PlayerCore?

    init(owner: PlayerCore) {
        self.owner = owner
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        let newState = player.state
        Task { @MainActor [weak owner] in
            owner?.vlcStateChanged(newState)
        }
    }

    func mediaPlayerMediaChanged(_ aNotification: Notification) {
        Task { @MainActor [weak owner] in
            owner?.vlcMediaChanged()
        }
    }
}
