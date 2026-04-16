# Sprint 11 — Subtitles, Buffering & Performance

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Napisy (OpenSubtitles API + AVPlayer subtitle tracks), pełna kontrola rozmiaru/stylu, agresywny pre-buffering, wskaźnik siły sygnału/bitratu, auto-retry na zerwaniu streamu.

**Architecture:**
- 11a: `SubtitleService` (AetherCore) — OpenSubtitles REST API v1, wyszukiwanie po nazwie kanału / tytule EPG
- 11b: `SubtitleOverlayView` — renderowanie SRT/WebVTT nad `VideoPlayerLayer`, font size / offset / kolor z `@AppStorage`
- 11c: `BufferingConfig` + `PlayerCore` tuning — `AVPlayerItem` preferred forward buffer, stall handler z auto-retry (max 3x), `BufferingIndicator` overlay
- 11d: `StreamStatsView` — bitrate / dropped frames / buffer fill live HUD (opcjonalny, toggle)

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, AVKit, URLSession, macOS 14+

---

## Task 1: SubtitleService — OpenSubtitles REST API v1

**Objective:** Wyszukaj i pobierz napisy SRT/VTT z opensubtitles.com.

**Files:**
- Create: `Sources/AetherCore/Services/SubtitleService.swift`
- Create: `Sources/AetherCore/Models/SubtitleTrack.swift`

**SubtitleTrack.swift:**
```swift
import Foundation

public struct SubtitleTrack: Identifiable, Sendable {
    public let id: String          // opensubtitles file_id
    public let language: String    // e.g. "pl", "en"
    public let languageName: String
    public let downloadURL: URL?   // filled after /download call
    public let rating: Double
    public let fileSize: Int

    public init(id: String, language: String, languageName: String,
                downloadURL: URL? = nil, rating: Double = 0, fileSize: Int = 0) {
        self.id = id
        self.language = language
        self.languageName = languageName
        self.downloadURL = downloadURL
        self.rating = rating
        self.fileSize = fileSize
    }
}
```

**SubtitleService.swift:**
```swift
import Foundation

/// Actor wrapping OpenSubtitles REST API v1.
/// Docs: https://opensubtitles.stoplight.io/docs/opensubtitles-api
public actor SubtitleService {

    // MARK: - Config

    /// Free-tier API key — get from https://www.opensubtitles.com/consumers
    /// Store in UserDefaults under "opensubtitles_api_key"
    public static var apiKey: String {
        UserDefaults.standard.string(forKey: "opensubtitles_api_key") ?? ""
    }

    private let baseURL = URL(string: "https://api.opensubtitles.com/api/v1")!
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: - Search

    /// Search subtitles by query string (EPG title or channel name).
    /// Returns up to 10 results sorted by rating desc.
    public func search(query: String, languages: [String] = ["pl", "en"]) async throws -> [SubtitleTrack] {
        guard !Self.apiKey.isEmpty else { throw SubtitleError.noAPIKey }

        var comps = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "languages", value: languages.joined(separator: ",")),
            URLQueryItem(name: "order_by", value: "rating"),
            URLQueryItem(name: "per_page", value: "10"),
        ]

        var req = URLRequest(url: comps.url!)
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

        let (data, _) = try await session.data(for: req)
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
```

**Commit:** `feat: SubtitleService — OpenSubtitles REST API v1`

---

## Task 2: SRTParser — parsuj SRT i WebVTT na [SubtitleCue]

**Objective:** Konwertuj tekst SRT/VTT na tablicę timed cue'ów.

**Files:**
- Create: `Sources/AetherCore/Parsers/SRTParser.swift`

```swift
import Foundation

public struct SubtitleCue: Sendable {
    public let start: TimeInterval   // seconds
    public let end: TimeInterval
    public let text: String
}

public enum SRTParser {
    /// Parses SRT or WebVTT subtitle text into an array of `SubtitleCue`.
    public static func parse(_ content: String) -> [SubtitleCue] {
        // Normalize line endings
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
                                .replacingOccurrences(of: "\r", with: "\n")
        // Strip BOM
        let stripped = normalized.hasPrefix("\u{FEFF}")
            ? String(normalized.dropFirst()) : normalized

        // Remove WebVTT header if present
        var text = stripped
        if text.hasPrefix("WEBVTT") {
            text = text.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
        }

        var cues: [SubtitleCue] = []
        let blocks = text.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                            .components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }

            // Find timecode line (may be preceded by index number)
            var timeLine = lines[0]
            var textStart = 1
            if !timeLine.contains("-->") && lines.count > 1 {
                timeLine = lines[1]
                textStart = 2
            }
            guard timeLine.contains("-->"),
                  let (start, end) = parseTimecode(timeLine) else { continue }

            let cueText = lines[textStart...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cueText.isEmpty else { continue }

            cues.append(SubtitleCue(start: start, end: end, text: cueText))
        }
        return cues
    }

    private static func parseTimecode(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2,
              let s = parseTime(parts[0].trimmingCharacters(in: .whitespaces)),
              let e = parseTime(parts[1].components(separatedBy: " ").first ?? "") else { return nil }
        return (s, e)
    }

    private static func parseTime(_ s: String) -> TimeInterval? {
        // Accepts HH:MM:SS,mmm  HH:MM:SS.mmm  MM:SS.mmm
        let clean = s.replacingOccurrences(of: ",", with: ".")
        let parts = clean.components(separatedBy: ":")
        if parts.count == 3,
           let h = Double(parts[0]), let m = Double(parts[1]), let sec = Double(parts[2]) {
            return h * 3600 + m * 60 + sec
        } else if parts.count == 2,
                  let m = Double(parts[0]), let sec = Double(parts[1]) {
            return m * 60 + sec
        }
        return nil
    }
}
```

**Commit:** `feat: SRTParser — SRT/WebVTT → [SubtitleCue]`

---

## Task 3: SubtitleStore — @MainActor ObservableObject

**Objective:** Przechowuj aktywne napisy, obsługuj wyszukiwanie + wybór ścieżki.

**Files:**
- Create: `Sources/AetherApp/SubtitleStore.swift`

```swift
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
```

**Commit:** `feat: SubtitleStore — ObservableObject wrapping SubtitleService`

---

## Task 4: SubtitleOverlayView — napisy nad video

**Objective:** Renderuj bieżący cue nad `VideoPlayerLayer`. Styl (rozmiar, offset, kolor, tło) z `@AppStorage`.

**Files:**
- Create: `Sources/AetherApp/Views/SubtitleOverlayView.swift`

```swift
import SwiftUI
import AetherCore

/// Transparent overlay rendering the current subtitle cue.
/// Place inside a ZStack over VideoPlayerLayer.
struct SubtitleOverlayView: View {
    @ObservedObject var store: SubtitleStore

    @AppStorage("subtitle_fontSize")   private var fontSize: Double = 22
    @AppStorage("subtitle_offsetY")    private var offsetY: Double = 32   // pts from bottom
    @AppStorage("subtitle_textColor")  private var textColorHex: String = "#FFFFFF"
    @AppStorage("subtitle_bgOpacity")  private var bgOpacity: Double = 0.55

    var body: some View {
        GeometryReader { geo in
            if let cue = store.currentCue {
                VStack {
                    Spacer()
                    Text(cue.text)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(Color(hex: textColorHex) ?? .white)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Color.black.opacity(bgOpacity),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .frame(maxWidth: geo.size.width * 0.85)
                        .padding(.bottom, offsetY)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: cue.text)
            }
        }
        .allowsHitTesting(false)  // don't block player interaction
    }
}

// MARK: - Color from hex

private extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
```

**Commit:** `feat: SubtitleOverlayView — cue renderer z AppStorage styling`

---

## Task 5: SubtitleSettingsView — panel ustawień napisów

**Objective:** Kontrolki: rozmiar czcionki, offset, kolor, przezroczystość tła, klucz API.

**Files:**
- Create: `Sources/AetherApp/Views/SubtitleSettingsView.swift`

```swift
import SwiftUI

struct SubtitleSettingsView: View {
    @AppStorage("subtitle_fontSize")   private var fontSize: Double = 22
    @AppStorage("subtitle_offsetY")    private var offsetY: Double = 32
    @AppStorage("subtitle_textColor")  private var textColorHex: String = "#FFFFFF"
    @AppStorage("subtitle_bgOpacity")  private var bgOpacity: Double = 0.55
    @AppStorage("opensubtitles_api_key") private var apiKey: String = ""

    var body: some View {
        Form {
            Section("OpenSubtitles") {
                TextField("API Key (opensubtitles.com → Consumers)", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Link("Get free API key →", destination: URL(string: "https://www.opensubtitles.com/consumers")!)
                    .font(.caption)
            }

            Section("Appearance") {
                HStack {
                    Text("Font size")
                    Spacer()
                    Slider(value: $fontSize, in: 14...48, step: 1)
                        .frame(width: 160)
                    Text("\(Int(fontSize)) pt")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                HStack {
                    Text("Bottom offset")
                    Spacer()
                    Slider(value: $offsetY, in: 8...120, step: 4)
                        .frame(width: 160)
                    Text("\(Int(offsetY)) pt")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                HStack {
                    Text("Background opacity")
                    Spacer()
                    Slider(value: $bgOpacity, in: 0...1, step: 0.05)
                        .frame(width: 160)
                    Text("\(Int(bgOpacity * 100))%")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                // Color picker — simple presets + custom
                HStack {
                    Text("Text color")
                    Spacer()
                    ForEach(["#FFFFFF", "#FFFF00", "#00FF00", "#FF6B6B"], id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .white)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(
                                textColorHex == hex ? Color.aetherAccent : Color.clear, lineWidth: 2))
                            .onTapGesture { textColorHex = hex }
                    }
                }
            }

            Section("Preview") {
                ZStack {
                    Color.black
                    Text("Przykładowy napis")
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(Color(hex: textColorHex) ?? .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(bgOpacity),
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .formStyle(.grouped)
    }
}

private extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
```

**Commit:** `feat: SubtitleSettingsView — API key + font/color/opacity controls`

---

## Task 6: Wbuduj SubtitleStore w AetherApp + SettingsView tab

**Objective:** `@StateObject subtitleStore`, `.environmentObject`, nowy tab „Subtitles" w `SettingsView`.

**Files:**
- Modify: `Sources/AetherApp/AetherApp.swift` — dodaj `@StateObject private var subtitleStore = SubtitleStore()`
- Modify: `Sources/AetherApp/Views/SettingsView.swift` — dodaj `TabViewItem("Subtitles", systemImage: "captions.bubble")`

W `AetherApp.swift` w `WindowGroup`:
```swift
.environmentObject(subtitleStore)
```

W `SettingsView.swift` w `TabView`:
```swift
SubtitleSettingsView()
    .tabItem { Label("Subtitles", systemImage: "captions.bubble") }
    .tag("subtitles")
```

**Commit:** `feat: wire SubtitleStore into app + Settings tab`

---

## Task 7: Wbuduj overlay + timer + SubtitlePicker w PlayerView

**Objective:** Napisy wyświetlają się nad video; `SubtitlePicker` (menu) w `PlayerControls`; ticker co 0.5s aktualizuje cue.

**Files:**
- Modify: `Sources/AetherApp/Views/PlayerView.swift`

Zmiany w `PlayerView.body`:

1. Dodaj `@EnvironmentObject private var subtitleStore: SubtitleStore`
2. Do `ZStack` nad `VideoPlayerLayer` dodaj:
```swift
SubtitleOverlayView(store: subtitleStore)
```
3. Dodaj ticker w `.onAppear`:
```swift
.onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
    let t = player.player.currentTime().seconds
    if t.isFinite { subtitleStore.updateCurrentCue(time: t) }
}
```
4. Dodaj auto-search gdy zmienia się kanał (`.onChange(of: player.currentChannel)`):
```swift
if let epgTitle = nowPlaying?.title, !epgTitle.isEmpty {
    subtitleStore.search(for: epgTitle)
} else if let name = newChannel?.name {
    subtitleStore.search(for: name)
}
```

5. W `PlayerControls` HStack wstaw `SubtitlePickerButton()` przed Dividerem przed FavoriteButton.

**SubtitlePickerButton (fileprivate w PlayerView.swift):**
```swift
fileprivate struct SubtitlePickerButton: View {
    @EnvironmentObject private var subtitleStore: SubtitleStore

    var body: some View {
        Menu {
            if subtitleStore.tracks.isEmpty && !subtitleStore.isSearching {
                Text("No subtitles found").foregroundStyle(.secondary)
            }
            if subtitleStore.isSearching {
                Text("Searching…").foregroundStyle(.secondary)
            }
            ForEach(subtitleStore.tracks) { track in
                Button(action: { subtitleStore.load(track: track) }) {
                    Label("\(track.languageName)  ★\(String(format: "%.1f", track.rating))",
                          systemImage: "captions.bubble")
                }
            }
            if subtitleStore.currentCue != nil || !subtitleStore.cues.isEmpty {
                Divider()
                Button("Clear subtitles", role: .destructive) { subtitleStore.clear() }
            }
        } label: {
            Image(systemName: subtitleStore.cues.isEmpty ? "captions.bubble" : "captions.bubble.fill")
                .font(.title3)
                .foregroundStyle(subtitleStore.cues.isEmpty ? Color.aetherText : Color.aetherAccent)
        }
        .menuStyle(.borderlessButton)
        .help("Subtitles")
    }
}
```

**Commit:** `feat: subtitle overlay + auto-search + picker in PlayerControls`

---

## Task 8: BufferingConfig — agresywne pre-buffering

**Objective:** Skonfiguruj `AVPlayerItem` dla minimalnego rebufferingu: duży forward buffer, szybki start.

**Files:**
- Create: `Sources/AetherCore/Player/BufferingConfig.swift`

```swift
import AVFoundation

/// Applies aggressive buffering settings to an `AVPlayerItem`.
public enum BufferingConfig {

    /// Preferred forward buffer in bytes — 32 MB (default is 50KB for HLS).
    public static let preferredForwardBufferDuration: TimeInterval = 30  // seconds

    /// Minimum buffer before playback can start.
    public static let automaticallyWaitsToMinimizeStalling: Bool = false

    public static func apply(to item: AVPlayerItem) {
        item.preferredForwardBufferDuration = preferredForwardBufferDuration
        // Do NOT set automaticallyWaitsToMinimizeStalling here — set on AVPlayer
    }

    public static func apply(to player: AVPlayer) {
        // False = start immediately, don't wait for optimal buffer
        player.automaticallyWaitsToMinimizeStalling = false
    }
}
```

W `PlayerCore.play(_:)` po `player.replaceCurrentItem(with: item)`:
```swift
BufferingConfig.apply(to: item)
BufferingConfig.apply(to: player)
```

**Commit:** `feat: BufferingConfig — 30s forward buffer, no stall wait`

---

## Task 9: Auto-retry na stall/error w PlayerCore

**Objective:** Gdy stream się zerwie (`AVPlayerItemFailedToPlayToEndTime` lub stall), auto-retry maks. 3x z exp. backoff.

**Files:**
- Modify: `Sources/AetherCore/Player/PlayerCore.swift`

Dodaj do klasy:
```swift
private var retryCount: Int = 0
private let maxRetries: Int = 3
private var stallObserver: NSObjectProtocol?
private var failedObserver: NSObjectProtocol?
```

Nowa metoda `scheduleRetry()`:
```swift
private func scheduleRetry() {
    guard retryCount < maxRetries, let channel = currentChannel else {
        state = .error("Stream unavailable after \(maxRetries) retries")
        return
    }
    retryCount += 1
    let delay = Double(retryCount) * 2.0   // 2s, 4s, 6s
    state = .loading
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(delay))
        play(channel)
    }
}
```

W `play(_:)` zresetuj licznik i zarejestruj obserwatory:
```swift
retryCount = 0
// register stall + failed observers
```

Zarejestruj `AVPlayerItemFailedToPlayToEndTimeNotification` i `AVPlayerItemPlaybackStalledNotification` → wywołaj `scheduleRetry()`.

**Commit:** `feat: PlayerCore auto-retry on stall/error (max 3x, exp backoff)`

---

## Task 10: BufferingIndicator overlay w PlayerView

**Objective:** Pokaż animowany spinner z napisem „Buffering… (2/3)" podczas stall-retry, zamiast zwykłego `ProgressView`.

**Files:**
- Modify: `Sources/AetherApp/Views/PlayerView.swift` — rozszerz `stateOverlay`

Zmień case `.loading` na:
```swift
case .loading:
    VStack(spacing: 10) {
        ProgressView()
            .scaleEffect(1.5)
            .tint(.white)
        if player.retryCount > 0 {
            Text("Buffering… (\(player.retryCount)/\(player.maxRetries))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
    .padding(16)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
```

Upublicznij `retryCount` i `maxRetries` w `PlayerCore` jako `@Published public private(set) var retryCount`.

**Commit:** `feat: BufferingIndicator — retry counter overlay`

---

## Task 11: StreamStatsView — live HUD bitratu

**Objective:** Opcjonalne HUD w rogu odtwarzacza: bitrate, dropped frames, buffer fill. Toggle przez toolbar.

**Files:**
- Create: `Sources/AetherApp/Views/StreamStatsView.swift`

```swift
import SwiftUI
import AVFoundation
import AetherCore

struct StreamStatsView: View {
    let player: AVPlayer
    @State private var stats = StreamStats()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            statRow("Bitrate", value: stats.bitrateKbps.map { "\($0) kbps" } ?? "—")
            statRow("Dropped", value: "\(stats.droppedFrames) frames")
            statRow("Buffer",  value: stats.bufferSeconds.map { String(format: "%.1fs", $0) } ?? "—")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            stats = StreamStats(player: player)
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
        }
    }
}

struct StreamStats {
    let bitrateKbps: Int?
    let droppedFrames: Int
    let bufferSeconds: Double?

    init() { bitrateKbps = nil; droppedFrames = 0; bufferSeconds = nil }

    init(player: AVPlayer) {
        // Indicated bitrate from HLS access log
        if let log = player.currentItem?.accessLog(),
           let event = log.events.last {
            bitrateKbps = event.indicatedBitrate > 0
                ? Int(event.indicatedBitrate / 1000) : nil
        } else {
            bitrateKbps = nil
        }

        // Dropped video frames
        droppedFrames = Int(player.currentItem?
            .accessLog()?.events.last?.numberOfDroppedVideoFrames ?? 0)

        // Loaded time ranges → buffer ahead
        if let item = player.currentItem,
           let range = item.loadedTimeRanges.first?.timeRangeValue {
            let current = item.currentTime().seconds
            let end = (range.start + range.duration).seconds
            bufferSeconds = max(0, end - current)
        } else {
            bufferSeconds = nil
        }
    }
}
```

W `PlayerView.body`, w `ZStack` nad video dodaj (pod SubtitleOverlayView):
```swift
if showStats {
    StreamStatsView(player: player.player)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
}
```

Stan `@State private var showStats = false` + toolbar button (ikon `chart.bar.xaxis`) w `PlayerControls`.

**Commit:** `feat: StreamStatsView — live bitrate/dropped/buffer HUD`

---

## Task 12: Push + verify CI green

```bash
git push origin main
# poll GitHub Actions until conclusion == "success"
```

**Expected:** ✅ CI green na macOS-15

---

## Verification

Po zakończeniu sprintu:
- Napisy ładują się automatycznie po włączeniu kanału z EPG title
- Menu napisów w playerze pokazuje dostępne ścieżki (PL/EN) z oceną
- Settings → Subtitles pozwala zmienić rozmiar/kolor/offset + wpisać API key
- Na zerwaniu streamu pojawia się „Buffering… (1/3)" i retry automatyczny
- HUD bitratu (toggle) widoczny w prawym górnym rogu
