import Foundation

/// Custom URLProtocol that intercepts HTTP requests and allows them to bypass ATS restrictions.
/// Registered in PlayerCore before creating AVURLAsset instances.
public final class HTTPBypassProtocol: URLProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var _dataTask: URLSessionDataTask?
    private var dataTask: URLSessionDataTask? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _dataTask
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _dataTask = newValue
        }
    }

    private static let bypassSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        config.urlCache = nil
        config.httpShouldUsePipelining = false
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        // Force HTTP/1.1 to avoid HTTP/2 partial message errors (no public API to disable HTTP/3)
        return URLSession(configuration: config)
    }()

    // File extensions routed through AVPlayer natively (not through HTTPBypassProtocol).
    // This protocol uses a non-streaming dataTask — intercepting large video files
    // causes it to buffer the entire file before passing data to AVPlayer.
    private static let directPlayExtensions: Set<String> = [
        "mp4", "m4v", "mov", "m3u8", "m3u", "mpd"
    ]
    // IPTV path prefixes already routed via LocalHLSProxy to localhost
    // (live, mkv, avi, wmv, ts) — but also skip them here as defence-in-depth.
    private static let iptvStreamPrefixes: Set<String> = ["live", "movie", "series", "timeshift"]

    public override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url,
              let scheme = url.scheme?.lowercased() else { return false }

        // NEVER intercept localhost — our local HLS server lives there
        if let host = url.host, host == "127.0.0.1" || host == "localhost" {
            return false
        }

        guard scheme == "http" || scheme == "https" else { return false }

        // Skip re-entrant requests from our own bypass session
        if URLProtocol.property(forKey: "HTTPBypassHandled", in: request) as? Bool == true {
            return false
        }

        // Skip direct-play video extensions — AVPlayer handles these natively
        // (NSAllowsArbitraryLoads=true in Info.plist already covers ATS).
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty && directPlayExtensions.contains(ext) { return false }

        // Skip IPTV stream paths (/live/ /movie/ /series/) as defence-in-depth —
        // LocalHLSProxy already handles unsupported formats via FFmpeg.
        let firstPathComponent = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        if iptvStreamPrefixes.contains(firstPathComponent) { return false }

        #if DEBUG
        print("[HTTPBypassProtocol] Intercepting: \(url.absoluteString)")
        #endif

        return true
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    nonisolated public override func startLoading() {
        let request = self.request
        guard self.client != nil else { return }

        var mutableRequest = request
        // Mark so canInit skips our own bypass session's requests
        URLProtocol.setProperty(true, forKey: "HTTPBypassHandled", in: &mutableRequest)

        if mutableRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            mutableRequest.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
        }

        #if DEBUG
        print("[HTTPBypassProtocol] Starting load: \(request.url?.absoluteString ?? "unknown")")
        #endif

        let task = Self.bypassSession.dataTask(with: mutableRequest) { [weak self] data, response, error in
            guard let self else { return }

            if let error = error as NSError? {
                let isSocketError = error.code == NSURLErrorNetworkConnectionLost ||
                                    error.code == NSURLErrorNotConnectedToInternet ||
                                    error.localizedDescription.contains("Socket is not connected")
                if isSocketError {
                    #if DEBUG
                    print("[HTTPBypassProtocol] Socket error — retrying with fresh session: \(error.localizedDescription)")
                    #endif
                    let freshConfig = URLSessionConfiguration.ephemeral
                    freshConfig.httpShouldUsePipelining = false
                    let freshSession = URLSession(configuration: freshConfig)
                    let retryTask = freshSession.dataTask(with: mutableRequest) { [weak self] d2, r2, e2 in
                        guard let self else { return }
                        Self.deliverResponse(d2, r2, e2, to: self.client, protocolInstance: self)
                    }
                    self.dataTask = retryTask
                    retryTask.resume()
                    return
                }
            }

            Self.deliverResponse(data, response, error, to: self.client, protocolInstance: self)
        }

        dataTask = task
        task.resume()
    }

    public override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }

    // MARK: - Response delivery

    private static func deliverResponse(
        _ data: Data?,
        _ response: URLResponse?,
        _ error: Error?,
        to client: URLProtocolClient?,
        protocolInstance: HTTPBypassProtocol
    ) {
        guard let client else { return }

        if let error = error {
            #if DEBUG
            print("[HTTPBypassProtocol] Error: \(error.localizedDescription)")
            #endif
            client.urlProtocol(protocolInstance, didFailWithError: error)
            return
        }

        if let response = response {
            #if DEBUG
            if let httpResponse = response as? HTTPURLResponse {
                print("[HTTPBypassProtocol] Response: \(httpResponse.statusCode)")
            }
            #endif
            client.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
        }

        if let data = data {
            #if DEBUG
            print("[HTTPBypassProtocol] Loaded \(data.count) bytes")
            #endif
            client.urlProtocol(protocolInstance, didLoad: data)
        }

        client.urlProtocolDidFinishLoading(protocolInstance)
    }
}
