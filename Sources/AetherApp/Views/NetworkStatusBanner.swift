import SwiftUI
import AetherCore

/// Network status indicator banner.
struct NetworkStatusBanner: View {
    @ObservedObject var networkMonitor: NetworkMonitorService

    var body: some View {
        Group {
            if !networkMonitor.isOnline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.white)

                    Text("No Internet Connection")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    Spacer()

                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: networkMonitor.isOnline)
    }
}
