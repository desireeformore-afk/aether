import SwiftUI
import AetherCore

public struct SeekBarView: View {
    @Bindable public var player: PlayerCore
    @State private var isSeeking = false
    @State private var seekPosition: Double = 0
    @State private var displayDuration: Double = 0
    @State private var isHovered = false
    @State private var hoverLocation: CGFloat = 0
    @State private var hoverFraction: Double = 0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init(player: PlayerCore) {
        self.player = player
    }

    /// Current displayed fraction of progress (0–1).
    private var fraction: Double {
        isSeeking
            ? seekPosition
            : (displayDuration > 0 ? min(player.currentTime / displayDuration, 1) : 0)
    }

    public var body: some View {
        VStack(spacing: 4) {
            // MARK: Custom seek track
            // SwiftUI Slider on macOS only triggers onEditingChanged when dragging,
            // NOT on tap. We use GeometryReader + explicit tap + drag gestures instead.
            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)

                    // Progress fill
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, fraction * width), height: 4)

                    // Thumb knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(radius: 2)
                        .offset(x: max(0, fraction * width - 6))
                        .animation(.interactiveSpring(response: 0.15), value: fraction)
                }
                .frame(height: 20)
                .scaleEffect(y: isHovered || isSeeking ? 1.75 : 1.0, anchor: .center)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.65), value: isHovered || isSeeking)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        isHovered = true
                        hoverLocation = location.x
                        hoverFraction = max(0, min(1, location.x / width))
                    case .ended:
                        isHovered = false
                    }
                }
                .onTapGesture { location in
                    guard displayDuration > 0, width > 0 else { return }
                    let f = max(0, min(1, location.x / width))
                    seekPosition = f
                    player.userSeek(to: f * displayDuration)
                }
                // Drag to scrub
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            guard width > 0 else { return }
                            isSeeking = true
                            seekPosition = max(0, min(1, value.location.x / width))
                        }
                        .onEnded { value in
                            defer { isSeeking = false }
                            guard displayDuration > 0, width > 0 else { return }
                            let f = max(0, min(1, value.location.x / width))
                            seekPosition = f
                            player.userSeek(to: f * displayDuration)
                        }
                )
            }
            .frame(height: 20)
            .overlay(alignment: .topLeading) {
                // PREMIUM HOVER TOOLTIP timestamp
                if isHovered && displayDuration > 0 {
                    let text = formatTime(hoverFraction * displayDuration)
                    Text(text)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        // Align the tooltip right above the cursor (offsetting the width of the tooltip so it centers)
                        .offset(x: hoverLocation - 20, y: -28)
                        .animation(.interactiveSpring(response: 0.1, dampingFraction: 0.8), value: hoverLocation)
                }
            }
            .onReceive(timer) { _ in
                guard !isSeeking else { return }
                let d = player.duration
                if d > 0 { displayDuration = d }
            }
            .onChange(of: player.state) { _, newState in
                if case .loading = newState {
                    seekPosition = 0
                    displayDuration = 0
                }
            }

            // Time labels
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
