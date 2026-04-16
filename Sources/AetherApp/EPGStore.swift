import Foundation
import AetherCore

/// Observable wrapper around `EPGService` to allow SwiftUI environment injection.
@MainActor
public final class EPGStore: ObservableObject {
    public let service = EPGService()

    public init() {}

    /// Loads an EPG guide from `url` and notifies subscribers.
    public func loadGuide(from url: URL, forceRefresh: Bool = false) async {
        do {
            try await service.loadGuide(from: url, forceRefresh: forceRefresh)
            objectWillChange.send()
        } catch {
            // Swallow — EPG is best-effort
            print("[EPGStore] Failed to load guide: \(error)")
        }
    }
}
