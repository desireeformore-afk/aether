import SwiftUI
import AetherCore
import Combine

@MainActor
final class SubtitleStore: ObservableObject {
    let service = SubtitleService()

    @Published private(set) var tracks: [SubtitleTrack] = []
    @Published private(set) var cues: [SubtitleCue] = []
    @Published private(set) var currentCue: SubtitleCue? = nil
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastError: String? = nil

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "opensubtitles_api_key") ?? ""
    }

    // MARK: - Search & load

    func search(for query: String) {
        guard !query.isEmpty else { return }
        isSearching = true
        lastError = nil
        let key = apiKey
        Task {
            do {
                tracks = try await service.search(query: query, apiKey: key)
            } catch {
                lastError = error.localizedDescription
            }
            isSearching = false
        }
    }

    func load(track: SubtitleTrack) {
        let key = apiKey
        Task {
            do {
                let url = try await service.downloadURL(for: track.id, apiKey: key)
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
