import Foundation

/// Downloads, caches, and queries EPG data from XMLTV sources.
public actor EPGService {

    // MARK: - State

    /// All loaded entries, keyed by channelID.
    private var entriesByChannel: [String: [EPGEntry]] = [:]
    private let cacheDirectory: URL
    private let parser = XMLTVParser()

    // MARK: - Init

    public init(cacheDirectory: URL? = nil) {
        if let dir = cacheDirectory {
            self.cacheDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = appSupport
                .appendingPathComponent("Aether", isDirectory: true)
                .appendingPathComponent("EPGCache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.cacheDirectory, withIntermediateDirectories: true
        )
    }

    // MARK: - Public API

    /// Loads an XMLTV feed from `url`, caches it, and indexes entries by channelID.
    ///
    /// - Parameters:
    ///   - url: Remote or local XMLTV URL.
    ///   - forceRefresh: Ignore disk cache when `true`.
    public func loadGuide(from url: URL, forceRefresh: Bool = false) async throws {
        let cacheFile = cacheURL(for: url)

        let data: Data
        if !forceRefresh, let cached = try? Data(contentsOf: cacheFile) {
            data = cached
        } else if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (downloaded, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw EPGServiceError.httpError(
                    (response as? HTTPURLResponse)?.statusCode ?? -1
                )
            }
            data = downloaded
            try data.write(to: cacheFile)
        }

        let entries = try await parser.parse(data: data)
        index(entries)
    }

    /// Returns all EPG entries for `channelID`.
    public func entries(for channelID: String) -> [EPGEntry] {
        entriesByChannel[channelID] ?? []
    }

    /// Returns the currently airing programme for `channelID`, if any.
    public func nowPlaying(for channelID: String, at date: Date = Date()) -> EPGEntry? {
        entries(for: channelID).first { $0.isOnAir(at: date) }
    }

    /// Returns the next programme after the current one for `channelID`.
    public func nextUp(for channelID: String, at date: Date = Date()) -> EPGEntry? {
        entries(for: channelID)
            .filter { $0.start > date }
            .min { $0.start < $1.start }
    }

    /// Returns today's schedule for `channelID`.
    public func todaySchedule(for channelID: String, at date: Date = Date()) -> [EPGEntry] {
        let cal = Calendar.current
        return entries(for: channelID).filter { cal.isDate($0.start, inSameDayAs: date) }
    }

    /// Clears all cached data.
    public func clearCache() {
        entriesByChannel = [:]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil
        )) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: - Private

    private func index(_ entries: [EPGEntry]) {
        var byChannel: [String: [EPGEntry]] = [:]
        for entry in entries {
            byChannel[entry.channelID, default: []].append(entry)
        }
        // Sort each channel's entries chronologically
        for key in byChannel.keys {
            byChannel[key]?.sort { $0.start < $1.start }
        }
        // Merge with existing (replace same-channel entries)
        for (cid, newEntries) in byChannel {
            entriesByChannel[cid] = newEntries
        }
    }

    private func cacheURL(for url: URL) -> URL {
        let hash = abs(url.absoluteString.hashValue)
        return cacheDirectory.appendingPathComponent("\(hash).xmltv")
    }
}

// MARK: - Errors

public enum EPGServiceError: Error, Sendable {
    case httpError(Int)
    case dataUnavailable
}
