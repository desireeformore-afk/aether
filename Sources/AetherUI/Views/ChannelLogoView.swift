import SwiftUI

/// Channel logo with URLCache (memory + disk), gradient initial placeholder, and fade-in.
public struct ChannelLogoView: View {
    let url: URL?
    let size: CGFloat
    let channelName: String

    public init(url: URL?, size: CGFloat = 40, channelName: String = "") {
        self.url = url
        self.size = size
        self.channelName = channelName
    }

    public var body: some View {
        Group {
            if let url {
                CachedAsyncImage(url: url, size: size, channelName: channelName)
            } else {
                ChannelInitialView(name: channelName, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - ChannelInitialView

/// Deterministic gradient badge showing the channel's first letter.
/// Used as placeholder while loading and as the error/fallback state.
struct ChannelInitialView: View {
    let name: String
    let size: CGFloat

    private var letter: String {
        name.first.map { String($0).uppercased() } ?? "•"
    }

    private var gradientColors: [Color] {
        let palettes: [[Color]] = [
            [.blue, .indigo],
            [.purple, .pink],
            [.red, .orange],
            [.orange, .yellow],
            [.green, .teal],
            [.teal, .cyan],
            [.indigo, .purple],
            [.pink, .red],
        ]
        let idx = Int((name.unicodeScalars.first?.value ?? 65) % UInt32(palettes.count))
        return palettes[idx]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(letter)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

// MARK: - CachedAsyncImage

private struct CachedAsyncImage: View {
    let url: URL
    let size: CGFloat
    let channelName: String

    /// 20 MB memory / 100 MB disk logo cache shared across the app.
    private static let imageCache = URLCache(
        memoryCapacity: 20 * 1024 * 1024,
        diskCapacity: 100 * 1024 * 1024,
        directory: FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Aether/LogoCache")
    )

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.25))) { phase in
            switch phase {
            case .empty:
                ChannelInitialView(name: channelName, size: size)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            case .failure:
                ChannelInitialView(name: channelName, size: size)
            @unknown default:
                EmptyView()
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        ChannelLogoView(url: nil, channelName: "BBC News")
        ChannelLogoView(url: nil, channelName: "Canal+")
        ChannelLogoView(url: nil, channelName: "HBO Max")
        ChannelLogoView(url: URL(string: "https://picsum.photos/80"), size: 60, channelName: "Test Channel")
    }
    .padding()
}
