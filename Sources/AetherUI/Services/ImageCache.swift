import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#endif

// MARK: - ImageCache

/// In-memory NSCache (200 images / 100 MB) backed by URLCache for disk persistence.
/// In-flight deduplication prevents the same URL from being fetched multiple times concurrently.
public actor ImageCache {
    public static let shared = ImageCache()

    private let store: NSCache<NSString, AnyObject> = {
        let c = NSCache<NSString, AnyObject>()
        c.countLimit = 200
        c.totalCostLimit = 100 * 1024 * 1024
        return c
    }()

    // Deduplicates concurrent requests for the same URL.
    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]

    private init() {}

    public func image(for url: URL) async -> PlatformImage? {
        let key = url.absoluteString as NSString
        let strKey = url.absoluteString

        // 1. In-memory hit
        if let obj = store.object(forKey: key), let img = obj as? PlatformImage {
            return img
        }

        // 2. URLCache (disk) hit
        let request = URLRequest(url: url)
        if let data = URLCache.shared.cachedResponse(for: request)?.data,
           let img = PlatformImage(data: data) {
            store.setObject(img as AnyObject, forKey: key, cost: data.count)
            return img
        }

        // 3. Deduplicate: join an existing in-flight fetch if one is already running.
        if let existing = inFlight[strKey] {
            return await existing.value
        }

        // 4. Start a new network fetch and register it so concurrent callers can join.
        let fetchTask = Task<PlatformImage?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                guard let img = PlatformImage(data: data) else { return nil }
                URLCache.shared.storeCachedResponse(
                    CachedURLResponse(response: response, data: data),
                    for: URLRequest(url: url)
                )
                return img
            } catch {
                return nil
            }
        }
        inFlight[strKey] = fetchTask
        let result = await fetchTask.value
        inFlight.removeValue(forKey: strKey)
        if let img = result {
            store.setObject(img as AnyObject, forKey: key, cost: 0)
        }
        return result
    }

    public func clear() {
        store.removeAllObjects()
        inFlight.removeAll()
    }
}

// MARK: - CachedImageView

/// SwiftUI view that loads an image via ImageCache with a placeholder until loaded.
public struct CachedImageView<Placeholder: View, Content: View>: View {
    let url: URL?
    let placeholder: () -> Placeholder
    let content: (Image) -> Content

    @State private var platformImage: PlatformImage?

    public init(
        url: URL?,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.url = url
        self.placeholder = placeholder
        self.content = content
    }

    public var body: some View {
        Group {
            if let img = platformImage {
                content(Image(platformImage: img))
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString) {
            platformImage = nil
            guard let url else { return }
            let loaded = await ImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) {
                platformImage = loaded
            }
        }
    }
}

// MARK: - Image convenience init

extension Image {
    public init(platformImage: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: platformImage)
        #elseif canImport(UIKit)
        self.init(uiImage: platformImage)
        #endif
    }
}
