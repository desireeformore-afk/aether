import SwiftUI
import AetherCore

struct BrandHubCard: View {
    let hub: BrandHub
    @State private var isHovered = false
    
    init(hub: BrandHub) {
        self.hub = hub
    }
    
    var body: some View {
        ZStack {
            // Base background
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            hub.themeColor.opacity(0.8),
                            hub.themeColor.opacity(0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Glass overlay
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isHovered ? 0 : 0.5)
            
            VStack(spacing: 12) {
                Image(systemName: hub.systemImage)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isHovered)
                
                Text(hub.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            // Border glow
            if isHovered {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            }
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: hub.themeColor.opacity(isHovered ? 0.6 : 0.2), radius: isHovered ? 15 : 5, y: isHovered ? 8 : 4)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .onHover { h in isHovered = h }
    }
}
