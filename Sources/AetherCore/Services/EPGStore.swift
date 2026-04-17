import Foundation

/// Observable wrapper around `EPGService` for SwiftUI environment injection.
/// Also manages per-playlist EPG loading triggered by playlist selection changes.
@MainActor
public final class EPGStore: ObservableObject {
    public let service = EPGService()

    /// Currently loaded EPG source URL (for display in Settings)
    @Published public private(set) var currentEPGURL: URL?
    /// Whether an EPG load is in progress.
    @Published public private(set) var isLoading = false
    /// Last error message (nil = no error).
    @Published public private(set) var lastError: String?

    public init() {}

    // MARK: - Public API

    /// Loads EPG for a given playlist. Uses `effectiveEPGURL` from the record.
    /// No-op if no EPG URL is available.
    public func loadGuide(for playlist: PlaylistRecord, forceRefresh: Bool = false) async {
        guard let url = playlist.effectiveEPGURL else {
            currentEPGURL = nil
            return
        }
        await loadGuide(from: url, forceRefresh: forceRefresh)
    }

    /// Loads EPG from an explicit URL.
    public func loadGuide(from url: URL, forceRefresh: Bool = false) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            try await service.loadGuide(from: url, forceRefresh: forceRefresh)
            currentEPGURL = url
            objectWillChange.send()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Clears EPG cache (in-memory + disk).
    public func clearCache() async {
        await service.clearCache()
        currentEPGURL = nil
        objectWillChange.send()
    }
}
