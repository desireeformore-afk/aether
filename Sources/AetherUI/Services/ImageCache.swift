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

    private static let imageRequestTimeout: TimeInterval = 8
    private static let imageResourceTimeout: TimeInterval = 20
    private static let imageMaximumConnectionsPerHost = 4
    private static let maxConcurrentImageDownloads = 4

    private let store: NSCache<NSString, AnyObject> = {
        let c = NSCache<NSString, AnyObject>()
        c.countLimit = 200
        c.totalCostLimit = 100 * 1024 * 1024
        return c
    }()

    private let session: URLSession

    // Deduplicates concurrent requests for the same URL.
    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]
    private var activeImageDownloads = 0
    private var imageDownloadWaiters: [CheckedContinuation<Void, Never>] = []

    private init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: Self.defaultSessionConfiguration())
    }

    private static func defaultSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = imageRequestTimeout
        config.timeoutIntervalForResource = imageResourceTimeout
        config.httpMaximumConnectionsPerHost = imageMaximumConnectionsPerHost
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = .shared
        config.waitsForConnectivity = false
        return config
    }

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
            await self.downloadImage(for: url)
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
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }

    private func downloadImage(for url: URL) async -> PlatformImage? {
        await acquireImageDownloadPermit()
        defer { releaseImageDownloadPermit() }

        do {
            try Task.checkCancellation()
            let request = URLRequest(
                url: url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: Self.imageRequestTimeout
            )
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard let img = PlatformImage(data: data) else { return nil }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data),
                for: request
            )
            store.setObject(img as AnyObject, forKey: url.absoluteString as NSString, cost: data.count)
            return img
        } catch {
            return nil
        }
    }

    private func acquireImageDownloadPermit() async {
        if activeImageDownloads < Self.maxConcurrentImageDownloads {
            activeImageDownloads += 1
            return
        }

        await withCheckedContinuation { continuation in
            imageDownloadWaiters.append(continuation)
        }
    }

    private func releaseImageDownloadPermit() {
        if imageDownloadWaiters.isEmpty {
            activeImageDownloads = max(0, activeImageDownloads - 1)
        } else {
            imageDownloadWaiters.removeFirst().resume()
        }
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
