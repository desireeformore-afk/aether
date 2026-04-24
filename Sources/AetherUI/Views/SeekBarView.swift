import SwiftUI
import AVFoundation
import AetherCore

public struct SeekBarView: View {
    @Bindable public var player: PlayerCore
    public var customDuration: Double?
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0
    @State private var duration: Double = 0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init(player: PlayerCore, customDuration: Double? = nil) {
        self.player = player
        self.customDuration = customDuration
    }

    public var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: isSeeking ? $seekPosition : Binding(
                    get: { duration > 0 ? player.currentTime / duration : 0 },
                    set: { _ in }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        let targetTime = seekPosition * duration
                        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
                        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                }
            )
            .accessibilityLabel("Seek position")
            .accessibilityValue(Text(formatTime(isSeeking ? seekPosition * duration : player.currentTime)))
            .onReceive(timer) { _ in
                if !isSeeking {
                    let raw = player.player.currentItem?.duration.seconds ?? 0
                    if raw.isNaN || raw.isInfinite || raw == .zero {
                        duration = customDuration ?? 0
                    } else {
                        duration = raw
                    }
                }
            }

            HStack {
                Text(formatTime(isSeeking ? seekPosition * duration : player.currentTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
