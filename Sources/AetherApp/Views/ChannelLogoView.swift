import SwiftUI
import AetherCore

/// Displays a channel logo from a URL with memory + disk caching via `URLCache`.
/// Falls back to a placeholder icon when no URL is given or load fails.
public struct ChannelLogoView: View {
    let url: URL?
    let size: CGFloat

    public init(url: URL?, size: CGFloat = 40) {
        self.url = url
        self.size = size
    }

    public var body: some View {
        Group {
            if let url {
                CachedAsyncImage(url: url, size: size)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholder: some View {
        Image(systemName: "tv")
            .resizable()
            .scaledToFit()
            .padding(size * 0.2)
            .foregroundStyle(Color.aetherSecondary)
            .frame(width: size, height: size)
            .background(Color.aetherSurface, in: RoundedRectangle(cornerRadius: size * 0.2))
    }
}

// MARK: - CachedAsyncImage

/// `AsyncImage` wrapper that uses `URLCache` (memory + disk) for logo images.
private struct CachedAsyncImage: View {
    let url: URL
    let size: CGFloat

    /// Shared URL cache: 20 MB memory, 100 MB disk.
    private static let imageCache = URLCache(
        memoryCapacity: 20 * 1024 * 1024,
        diskCapacity: 100 * 1024 * 1024,
        directory: FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Aether/LogoCache")
    )

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: size, height: size)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
            case .failure:
                Image(systemName: "tv.slash")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .foregroundStyle(Color.aetherSecondary)
                    .frame(width: size, height: size)
                    .background(Color.aetherSurface, in: RoundedRectangle(cornerRadius: size * 0.2))
            @unknown default:
                EmptyView()
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        ChannelLogoView(url: nil)
        ChannelLogoView(url: URL(string: "https://picsum.photos/80"), size: 60)
    }
    .padding()
}
