import Foundation
import AVFoundation

/// Proxies HTTP streaming through AVAssetResourceLoaderDelegate to bypass
/// AVPlayer's built-in HTTP handler which fails on live MPEG-TS streams
/// (sends byte-range requests that IPTV servers reject with -12939).
///
/// Flow: AVPlayer → custom scheme "aether-live://" → this delegate → real "http://" via URLSession
public final class StreamProxyLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate {

    public static let scheme = "aether-live"

    private var session: URLSession!
    private var activeTasks: [Int: AVAssetResourceLoadingRequest] = [:] // taskIdentifier → request

    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 0 // No timeout for live streams
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - URL Conversion

    /// Convert http(s):// URL to custom scheme for resource loader interception.
    public static func proxyURL(from original: URL) -> URL? {
        guard var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else { return nil }
        // Encode original scheme: aether-live for http, aether-lives for https
        components.scheme = original.scheme == "https" ? "\(scheme)s" : scheme
        return components.url
    }

    /// Convert custom scheme back to original http(s)://.
    private static func originalURL(from proxy: URL) -> URL? {
        guard var components = URLComponents(url: proxy, resolvingAgainstBaseURL: false) else { return nil }
        let originalScheme = proxy.scheme?.hasSuffix("s") == true ? "https" : "http"
        components.scheme = originalScheme
        return components.url
    }

    // MARK: - AVAssetResourceLoaderDelegate

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let proxyURL = loadingRequest.request.url,
              let originalURL = Self.originalURL(from: proxyURL) else {
            return false
        }

        print("[StreamProxy] → \(originalURL.lastPathComponent)")

        var request = URLRequest(url: originalURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // Critical: do NOT send Range header — that's what causes -12939
        request.setValue(nil, forHTTPHeaderField: "Range")

        let task = session.dataTask(with: request)
        activeTasks[task.taskIdentifier] = loadingRequest
        task.resume()

        return true
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        for (id, req) in activeTasks where req === loadingRequest {
            session.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == id }?.cancel()
            }
            activeTasks.removeValue(forKey: id)
            break
        }
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let loadingRequest = activeTasks[dataTask.taskIdentifier] else {
            completionHandler(.cancel)
            return
        }

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        let mimeType = response.mimeType ?? "unknown"
        print("[StreamProxy] ← HTTP \(statusCode), MIME: \(mimeType)")

        // Reject non-2xx responses
        guard statusCode >= 200, statusCode < 400 else {
            let error = NSError(
                domain: "StreamProxy",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(statusCode)"]
            )
            loadingRequest.finishLoading(with: error)
            activeTasks.removeValue(forKey: dataTask.taskIdentifier)
            completionHandler(.cancel)
            return
        }

        // Fill content information — the KEY fix:
        // isByteRangeAccessSupported = false tells AVPlayer not to send Range headers
        if let contentInfo = loadingRequest.contentInformationRequest {
            contentInfo.isByteRangeAccessSupported = false

            // Content type as UTI
            switch mimeType {
            case "video/mp2t":
                contentInfo.contentType = "public.mpeg-2-transport-stream"
            case "video/mp4", "video/x-m4v":
                contentInfo.contentType = "public.mpeg-4"
            case "application/octet-stream":
                // Common for IPTV servers that don't set proper MIME
                contentInfo.contentType = "public.mpeg-2-transport-stream"
            default:
                contentInfo.contentType = "public.mpeg-2-transport-stream"
            }

            // Content length: use server's value if available, otherwise unknown
            let length = response.expectedContentLength
            if length > 0 {
                contentInfo.contentLength = length
            }
            // If unknown (-1), don't set — AVPlayer handles this
        }

        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let loadingRequest = activeTasks[dataTask.taskIdentifier] else { return }
        loadingRequest.dataRequest?.respond(with: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        guard let loadingRequest = activeTasks.removeValue(forKey: id) else { return }

        if loadingRequest.isFinished || loadingRequest.isCancelled { return }

        if let error = error as? NSError, error.code != NSURLErrorCancelled {
            print("[StreamProxy] ✗ \(error.localizedDescription)")
            loadingRequest.finishLoading(with: error)
        } else if error == nil {
            loadingRequest.finishLoading()
        }
    }

    // MARK: - Cleanup

    public func cancelAll() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        for (_, req) in activeTasks {
            if !req.isFinished && !req.isCancelled {
                req.finishLoading(with: NSError(domain: "StreamProxy", code: -999))
            }
        }
        activeTasks.removeAll()
    }

    deinit {
        cancelAll()
        session.invalidateAndCancel()
    }
}
