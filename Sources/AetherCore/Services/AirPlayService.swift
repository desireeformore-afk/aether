import Foundation
import Observation
@preconcurrency import AVFoundation

#if os(macOS)
@MainActor
@Observable
public final class AirPlayService {
    public static let shared = AirPlayService()

    public private(set) var isAirPlaying = false
    public private(set) var connectedDeviceName: String?
    public private(set) var availableDevices: [String] = []

    private var routeDetector: AVRouteDetector?
    private var player: AVPlayer?

    private init() {
        setupRouteDetection()
    }

    private func setupRouteDetection() {
        routeDetector = AVRouteDetector()
        routeDetector?.isRouteDetectionEnabled = true
    }

    public func setPlayer(_ player: AVPlayer) {
        self.player = player
        player.allowsExternalPlayback = true
        #if os(iOS) || os(tvOS)
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        #endif
        updateAirPlayStatus()
    }

    private func updateAirPlayStatus() {
        guard let player = player else {
            isAirPlaying = false
            connectedDeviceName = nil
            return
        }

        isAirPlaying = player.isExternalPlaybackActive
        connectedDeviceName = isAirPlaying ? "AirPlay Device" : nil
    }

    public func showAirPlayPicker() {
        // macOS uses system AirPlay menu
    }
}
#else
@MainActor
@Observable
public final class AirPlayService {
    public static let shared = AirPlayService()

    public private(set) var isAirPlaying = false
    public private(set) var connectedDeviceName: String?
    public private(set) var availableDevices: [String] = []

    private var routeDetector: AVRouteDetector?
    private var player: AVPlayer?

    private init() {
        setupRouteDetection()
    }

    private func setupRouteDetection() {
        routeDetector = AVRouteDetector()
        routeDetector?.isRouteDetectionEnabled = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        Task { @MainActor in
            updateAirPlayStatus()
        }
    }

    public func setPlayer(_ player: AVPlayer) {
        self.player = player
        player.allowsExternalPlayback = true
        #if os(iOS) || os(tvOS)
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        #endif
        updateAirPlayStatus()
    }

    private func updateAirPlayStatus() {
        guard let player = player else {
            isAirPlaying = false
            connectedDeviceName = nil
            return
        }

        isAirPlaying = player.isExternalPlaybackActive

        if isAirPlaying {
            #if os(iOS) || os(tvOS)
            let currentRoute = AVAudioSession.sharedInstance().currentRoute
            connectedDeviceName = currentRoute.outputs.first?.portName
            #else
            connectedDeviceName = "AirPlay Device"
            #endif
        } else {
            connectedDeviceName = nil
        }
    }

    public func showAirPlayPicker() {
        // iOS AirPlay picker would be shown via AVRoutePickerView
    }
}
#endif
