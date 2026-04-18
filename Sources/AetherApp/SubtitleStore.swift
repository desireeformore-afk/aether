import SwiftUI
import AetherCore
import Combine

@MainActor
@Observable
final class SubtitleStore {
    let service = SubtitleService()

    private(set) var tracks: [SubtitleTrack] = []
    private(set) var cues: [SubtitleCue] = []
    private(set) var currentCue: SubtitleCue? = nil
    private(set) var isSearching: Bool = false
    private(set) var lastError: String? = nil

    // MARK: - Search & load

    func search(for query: String) {
        guard !query.isEmpty else { return }
        isSearching = true
        lastError = nil
        Task {
            do {
                tracks = try await service.search(query: query)
            } catch {
                lastError = error.localizedDescription
            }
            isSearching = false
        }
    }

    func load(track: SubtitleTrack) {
        Task {
            do {
                let url = try await service.downloadURL(for: track.id)
                let content = try await service.fetchContent(url: url)
                cues = SRTParser.parse(content)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func clear() {
        tracks = []
        cues = []
        currentCue = nil
        lastError = nil
    }

    // MARK: - Tick (called by PlayerView with AVPlayer.currentTime())

    func updateCurrentCue(time: TimeInterval) {
        currentCue = cues.first { $0.start <= time && $0.end > time }
    }
}
