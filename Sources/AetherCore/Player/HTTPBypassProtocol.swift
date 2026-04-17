import Foundation

/// Custom URLProtocol that intercepts HTTP requests and allows them to bypass ATS restrictions.
/// Registered in PlayerCore before creating AVURLAsset instances.
public final class HTTPBypassProtocol: URLProtocol, @unchecked Sendable {
    
    private var dataTask: URLSessionDataTask?
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
        // Only intercept HTTP (not HTTPS) requests
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http"
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    public override func startLoading() {
        guard let client = client else { return }
        
        var mutableRequest = (request as NSURLRequest).mutableCopy() as! URLRequest
        
        // Add standard headers if missing
        if mutableRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            mutableRequest.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
        }
        
        dataTask = Self.bypassSession.dataTask(with: mutableRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                client.urlProtocol(self, didFailWithError: error)
                return
            }
            
            if let response = response {
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            
            if let data = data {
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
