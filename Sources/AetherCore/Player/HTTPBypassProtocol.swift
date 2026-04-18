import Foundation

/// Custom URLProtocol that intercepts HTTP requests and allows them to bypass ATS restrictions.
/// Registered in PlayerCore before creating AVURLAsset instances.
public final class HTTPBypassProtocol: URLProtocol {

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
        // Disable ATS for this session
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    // MARK: - URLProtocol overrides
    
    public override class func canInit(with request: URLRequest) -> Bool {
        // Intercept both HTTP and HTTPS requests for IPTV streams
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        let shouldIntercept = scheme == "http" || scheme == "https"
        
        #if DEBUG
        if shouldIntercept {
            print("[HTTPBypassProtocol] Intercepting: \(request.url?.absoluteString ?? "unknown")")
        }
        #endif
        
        return shouldIntercept
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    public override func startLoading() {
        guard let client = self.client else { return }
        let request = self.request
        
        var mutableRequest = request
        
        // Add standard headers if missing
        if mutableRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            mutableRequest.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
        }
        
        #if DEBUG
        print("[HTTPBypassProtocol] Starting load: \(request.url?.absoluteString ?? "unknown")")
        #endif
        
        dataTask = Self.bypassSession.dataTask(with: mutableRequest) { [weak self] data, response, error in
            guard let self = self, let client = self.client else { return }
            
            if let error = error {
                #if DEBUG
                print("[HTTPBypassProtocol] Error: \(error.localizedDescription)")
                #endif
                client.urlProtocol(self, didFailWithError: error)
                return
            }
            
            if let response = response {
                #if DEBUG
                if let httpResponse = response as? HTTPURLResponse {
                    print("[HTTPBypassProtocol] Response: \(httpResponse.statusCode)")
                }
                #endif
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            
            if let data = data {
                #if DEBUG
                print("[HTTPBypassProtocol] Loaded \(data.count) bytes")
                #endif
                client.urlProtocol(self, didLoad: data)
            }
            
            client.urlProtocolDidFinishLoading(self)
        }
        
        dataTask?.resume()
    }
    
    public override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }
}
