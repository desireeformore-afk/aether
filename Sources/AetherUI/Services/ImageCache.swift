import Foundation
import ImageIO
import SwiftUI

#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#endif

// MARK: - ImageCache

/// In-memory NSCache (200 image payloads / 100 MB) backed by URLCache for disk persistence.
/// In-flight deduplication prevents the same URL from being fetched multiple times concurrently.
public actor ImageCache {
    public static let shared = ImageCache()

    private static let imageRequestTimeout: TimeInterval = 8
    private static let imageResourceTimeout: TimeInterval = 20
    private static let imageMaximumConnectionsPerHost = 4
    private static let maxConcurrentImageDownloads = 4

    private let store: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 200
        c.totalCostLimit = 100 * 1024 * 1024
        return c
    }()

    private let session: URLSession

    // Deduplicates concurrent requests for the same URL.
    private var inFlight: [String: Task<Data?, Never>] = [:]
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

    public func imageData(for url: URL) async -> Data? {
        let key = url.absoluteString as NSString
        let strKey = url.absoluteString

        // 1. In-memory hit
        if let data = store.object(forKey: key) {
            return data as Data
        }

        // 2. URLCache (disk) hit
        let request = URLRequest(url: url)
        if let data = URLCache.shared.cachedResponse(for: request)?.data,
           Self.isDecodableImageData(data) {
            store.setObject(data as NSData, forKey: key, cost: data.count)
            return data
        }

        // 3. Deduplicate: join an existing in-flight fetch if one is already running.
        if let existing = inFlight[strKey] {
            return await existing.value
        }

        // 4. Start a new network fetch and register it so concurrent callers can join.
        let fetchTask = Task<Data?, Never> {
            await self.downloadImageData(for: url)
        }
        inFlight[strKey] = fetchTask
        let result = await fetchTask.value
        inFlight.removeValue(forKey: strKey)
        if let data = result {
            store.setObject(data as NSData, forKey: key, cost: data.count)
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

    private func downloadImageData(for url: URL) async -> Data? {
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
            guard Self.isDecodableImageData(data) else { return nil }
            URLCache.shared.storeCachedResponse(
                CachedURLResponse(response: response, data: data),
                for: request
            )
            store.setObject(data as NSData, forKey: url.absoluteString as NSString, cost: data.count)
            return data
        } catch {
            return nil
        }
    }

    private static func isDecodableImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
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
            await resetImage()
            guard let url else { return }
            let data = await ImageCache.shared.imageData(for: url)
            guard !Task.isCancelled else { return }
            await applyImageData(data)
        }
    }

    @MainActor
    private func resetImage() {
        platformImage = nil
    }

    @MainActor
    private func applyImageData(_ data: Data?) {
        let loaded = data.flatMap(PlatformImage.init(data:))
        guard !Task.isCancelled else { return }
        if loaded == nil {
            platformImage = nil
            return
        }
        withAnimation(.easeIn(duration: 0.25)) {
            platformImage = loaded
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
