import SwiftUI
import AetherCore

/// Transparent overlay rendering the current subtitle cue.
/// Place inside a ZStack over VideoPlayerLayer.
struct SubtitleOverlayView: View {
    @ObservedObject var store: SubtitleStore

    @AppStorage("subtitle_fontSize")   private var fontSize: Double = 22
    @AppStorage("subtitle_offsetY")    private var offsetY: Double = 32   // pts from bottom
    @AppStorage("subtitle_textColor")  private var textColorHex: String = "#FFFFFF"
    @AppStorage("subtitle_bgOpacity")  private var bgOpacity: Double = 0.55

    var body: some View {
        GeometryReader { geo in
            if let cue = store.currentCue {
                VStack {
                    Spacer()
                    Text(cue.text)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(Color(hex: textColorHex) ?? .white)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Color.black.opacity(bgOpacity),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .frame(maxWidth: geo.size.width * 0.85)
                        .padding(.bottom, offsetY)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: cue.text)
            }
        }
        .allowsHitTesting(false)  // don't block player interaction
    }
}

// MARK: - Color from hex

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
