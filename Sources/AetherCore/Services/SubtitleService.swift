import Foundation

/// Actor wrapping OpenSubtitles REST API v1.
/// Docs: https://opensubtitles.stoplight.io/docs/opensubtitles-api
public actor SubtitleService {

    // MARK: - Config

    /// Free-tier API key — get from https://www.opensubtitles.com/consumers
    /// Store in UserDefaults under "opensubtitles_api_key"
    nonisolated public static var apiKey: String {
        UserDefaults.standard.string(forKey: "opensubtitles_api_key") ?? ""
    }

    private let baseURL: URL
    private let session: URLSession

    public init() {
        guard let url = URL(string: "https://api.opensubtitles.com/api/v1") else {
            preconditionFailure("Invalid OpenSubtitles API base URL")
        }
        self.baseURL = url
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: - Search

    /// Search subtitles by query string (EPG title or channel name).
    /// Returns up to 10 results sorted by rating desc.
    public func search(query: String, languages: [String] = ["en"]) async throws -> [SubtitleTrack] {
        guard !Self.apiKey.isEmpty else { throw SubtitleError.noAPIKey }

        guard var comps = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false) else {
            throw SubtitleError.invalidURL
        }
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "languages", value: languages.joined(separator: ",")),
            URLQueryItem(name: "order_by", value: "rating"),
            URLQueryItem(name: "per_page", value: "10"),
        ]

        guard let url = comps.url else {
            throw SubtitleError.invalidURL
        }
        var req = URLRequest(url: url)
        req.addValue(Self.apiKey, forHTTPHeaderField: "Api-Key")
        req.addValue("Aether v1.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw SubtitleError.apiError((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoded = try JSONDecoder().decode(OSSearchResponse.self, from: data)
        return decoded.data.map { item in
            SubtitleTrack(
                id: String(item.attributes.files.first?.fileID ?? 0),
                language: item.attributes.language,
                languageName: item.attributes.languageName,
                rating: item.attributes.ratings,
                fileSize: item.attributes.files.first?.fileSize ?? 0
            )
        }
    }

    // MARK: - Download

    /// Fetches the actual download URL for a subtitle file_id.
    /// Free tier: 5 downloads/day per IP without login.
    public func downloadURL(for fileID: String) async throws -> URL {
        guard !Self.apiKey.isEmpty else { throw SubtitleError.noAPIKey }

        var req = URLRequest(url: baseURL.appendingPathComponent("download"))
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(Self.apiKey, forHTTPHeaderField: "Api-Key")
        req.addValue("Aether v1.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(["file_id": Int(fileID) ?? 0])

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SubtitleError.apiError(0) }
        // 406 = daily download quota exceeded; 401 = bad API key
        guard (200..<300).contains(http.statusCode) else {
            throw SubtitleError.apiError(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(OSDownloadResponse.self, from: data)
        guard let url = URL(string: decoded.link) else { throw SubtitleError.invalidURL }
        return url
    }

    // MARK: - Fetch content

    /// Downloads and returns subtitle file content as String.
    public func fetchContent(url: URL) async throws -> String {
        let (data, _) = try await session.data(from: url)
        guard let text = String(data: data, encoding: .utf8) ??
                         String(data: data, encoding: .isoLatin1) else {
            throw SubtitleError.decodeError
        }
        return text
    }
}

// MARK: - Errors

public enum SubtitleError: LocalizedError, Sendable {
    case noAPIKey
    case apiError(Int)
    case invalidURL
    case decodeError

    public var errorDescription: String? {
        switch self {
        case .noAPIKey: return "OpenSubtitles API key not configured (Settings → Subtitles)"
        case .apiError(let code): return "OpenSubtitles API error \(code)"
        case .invalidURL: return "Invalid subtitle download URL"
        case .decodeError: return "Could not decode subtitle file"
        }
    }
}

// MARK: - Codable DTOs (private)

private struct OSSearchResponse: Decodable {
    let data: [OSItem]
}

private struct OSItem: Decodable {
    let attributes: OSAttributes
}

private struct OSAttributes: Decodable {
    let language: String
    let languageName: String
    let ratings: Double
    let files: [OSFile]

    enum CodingKeys: String, CodingKey {
        case language, ratings, files
        case languageName = "language_name"
    }
}

private struct OSFile: Decodable {
    let fileID: Int
    let fileSize: Int

    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case fileSize = "file_size"
    }
}

private struct OSDownloadResponse: Decodable {
    let link: String
}
