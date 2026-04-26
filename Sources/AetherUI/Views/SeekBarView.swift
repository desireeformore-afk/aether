import SwiftUI
import AetherCore

public struct SeekBarView: View {
    @Bindable public var player: PlayerCore
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0   // 0.0 – 1.0 (fraction)
    @State private var displayDuration: Double = 0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init(player: PlayerCore) {
        self.player = player
    }

    public var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: isSeeking ? $seekPosition : Binding(
                    get: { displayDuration > 0 ? player.currentTime / displayDuration : 0 },
                    set: { _ in }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing {
                        guard displayDuration > 0, seekPosition > 0.005 else { return }
                        player.userSeek(to: seekPosition * displayDuration)
                    }
                }
            )
            .accessibilityLabel("Seek position")
            .accessibilityValue(Text(formatTime(isSeeking ? seekPosition * displayDuration : player.currentTime)))
            .onReceive(timer) { _ in
                if !isSeeking {
                    // VLC gives us duration directly — no ffprobe needed
                    let d = player.duration
                    if d > 0 { displayDuration = d }
                }
            }
            .onChange(of: player.state) { _, newState in
                // When a new channel starts, reset the bar
                if case .loading = newState {
                    seekPosition = 0
                    displayDuration = 0
                }
            }

            HStack {
                Text(formatTime(isSeeking ? seekPosition * displayDuration : player.currentTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(displayDuration))
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
