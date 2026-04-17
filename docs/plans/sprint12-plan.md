# Sprint 12 Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Polish UX, add Series browser (Xtream Codes), keyboard-driven channel search, playlist health-check, and unit tests for SRTParser + BufferingConfig.

**Architecture:** Modular — new features as standalone Views/Services in existing AetherApp/AetherCore structure. No new packages needed.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVFoundation, AetherCore (actor services), XstreamService (existing)

---

## Context

Existing modules (all CI-green after Sprint 11):
- `XstreamService` — actor, supports VOD + live streams. **Missing**: Series (get_series, get_series_categories, get_series_info).
- `VODBrowserView` — fully working VOD browser with category sidebar + grid.
- `PlayerView` — controls bar has room for a "Series" button next to VOD.
- `SubtitleStore` / `SRTParser` — no unit tests yet.
- `BufferingConfig` — no unit tests yet.
- `ChannelListView` — search is client-side filter only; no keyboard shortcut to focus it.
- `PlaylistService` — loads M3U/Xtream but no validation/health-check.

---

## Task 1: XstreamSeries models + service methods

**Objective:** Add Series data models and three new methods to `XstreamService`.

**Files:**
- Modify: `Sources/AetherCore/Services/XstreamService.swift`

**Implementation:**

Add after the `XstreamVOD` struct (around line 129):

```swift
/// A series category from Xtream Codes.
public struct XstreamSeriesCategory: Decodable, Sendable, Identifiable, Hashable, Equatable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey {
        case id = "category_id"
        case name = "category_name"
    }
}

/// Top-level series entry (list view).
public struct XstreamSeries: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let cover: String?
    public let plot: String?
    public let cast: String?
    public let director: String?
    public let genre: String?
    public let releaseDate: String?
    public let rating: String?
    public let categoryID: String?

    enum CodingKeys: String, CodingKey {
        case id = "series_id"
        case name, cover, plot, cast, director, genre, rating
        case releaseDate = "releaseDate"
        case categoryID = "category_id"
    }
}

/// Episode within a series season.
public struct XstreamEpisode: Decodable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let season: Int
    public let episodeNum: Int
    public let containerExtension: String?
    public let info: EpisodeInfo?

    public struct EpisodeInfo: Decodable, Sendable {
        public let plot: String?
        public let durationSecs: Int?
        public let rating: String?
        enum CodingKeys: String, CodingKey {
            case plot
            case durationSecs = "duration_secs"
            case rating
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title = "title"
        case season
        case episodeNum = "episode_num"
        case containerExtension = "container_extension"
        case info
    }
}

/// Detailed series info with episodes grouped by season.
public struct XstreamSeriesInfo: Decodable, Sendable {
    public let series: XstreamSeries
    /// Key = season number string ("1", "2", …)
    public let episodes: [String: [XstreamEpisode]]

    enum CodingKeys: String, CodingKey {
        case series = "info"
        case episodes
    }
}
```

Add three methods inside `XstreamService` (after `vodStreams`):

```swift
// MARK: - Series

/// Fetches all series categories.
public func seriesCategories() async throws -> [XstreamSeriesCategory] {
    try await get(queryItems: [
        URLQueryItem(name: "action", value: "get_series_categories")
    ])
}

/// Fetches series list, optionally filtered by category.
public func seriesList(categoryID: String? = nil) async throws -> [XstreamSeries] {
    var items = [URLQueryItem(name: "action", value: "get_series")]
    if let cid = categoryID {
        items.append(URLQueryItem(name: "category_id", value: cid))
    }
    return try await get(queryItems: items)
}

/// Fetches full info + episode list for a series.
public func seriesInfo(seriesID: Int) async throws -> XstreamSeriesInfo {
    try await get(queryItems: [
        URLQueryItem(name: "action", value: "get_series_info"),
        URLQueryItem(name: "series_id", value: "\(seriesID)")
    ])
}
```

**Verify:** `swift build` — no errors.

---

## Task 2: SeriesBrowserView — category sidebar + series grid

**Objective:** Series browser sheet mirroring VODBrowserView structure.

**Files:**
- Create: `Sources/AetherApp/Views/SeriesBrowserView.swift`

```swift
import SwiftUI
import AetherCore

struct SeriesBrowserView: View {
    let credentials: XstreamCredentials
    @ObservedObject var player: PlayerCore

    @State private var categories: [XstreamSeriesCategory] = []
    @State private var seriesList: [XstreamSeries] = []
    @State private var selectedCategory: XstreamSeriesCategory?
    @State private var isLoadingCategories = false
    @State private var isLoadingList = false
    @State private var searchText = ""
    @State private var selectedSeries: XstreamSeries?

    private let service: XstreamService

    init(credentials: XstreamCredentials, player: PlayerCore) {
        self.credentials = credentials
        self.player = player
        self.service = XstreamService(credentials: credentials)
    }

    var body: some View {
        NavigationSplitView {
            categoryList
        } detail: {
            seriesGrid
        }
        .navigationTitle("Series")
        .frame(minWidth: 720, minHeight: 500)
        .task { await loadCategories() }
        .sheet(item: $selectedSeries) { series in
            SeriesDetailView(series: series, credentials: credentials, player: player)
        }
    }

    private var categoryList: some View {
        List(selection: $selectedCategory) {
            if isLoadingCategories {
                ProgressView("Loading categories…")
            } else {
                ForEach(categories) { cat in
                    Text(cat.name)
                        .font(.aetherBody)
                        .tag(cat)
                }
            }
        }
        .navigationTitle("Categories")
        .onChange(of: selectedCategory) { _, cat in
            guard let cat else { return }
            Task { await loadList(for: cat) }
        }
    }

    private var seriesGrid: some View {
        Group {
            if isLoadingList {
                ProgressView("Loading series…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredList.isEmpty && selectedCategory != nil {
                ContentUnavailableView("No Series", systemImage: "tv")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedCategory == nil {
                ContentUnavailableView(
                    "Pick a Category",
                    systemImage: "rectangle.stack.fill",
                    description: Text("Select a category from the sidebar.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                        ForEach(filteredList) { series in
                            SeriesCard(series: series)
                                .onTapGesture { selectedSeries = series }
                        }
                    }
                    .padding()
                }
                .searchable(text: $searchText, prompt: "Search series")
            }
        }
        .background(Color.aetherBackground)
    }

    private var filteredList: [XstreamSeries] {
        guard !searchText.isEmpty else { return seriesList }
        return seriesList.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func loadCategories() async {
        isLoadingCategories = true
        defer { isLoadingCategories = false }
        categories = (try? await service.seriesCategories()) ?? []
    }

    private func loadList(for category: XstreamSeriesCategory) async {
        seriesList = []
        isLoadingList = true
        defer { isLoadingList = false }
        seriesList = (try? await service.seriesList(categoryID: category.id)) ?? []
    }
}

// MARK: - SeriesCard

private struct SeriesCard: View {
    let series: XstreamSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure, .empty:
                    ZStack {
                        Color.aetherSurface
                        Image(systemName: "tv")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color.aetherSurface
                }
            }
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(series.name)
                .font(.aetherCaption)
                .foregroundStyle(Color.aetherText)
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)
        }
    }
}
```

**Verify:** `swift build`

---

## Task 3: SeriesDetailView — season/episode picker + play

**Objective:** Sheet showing series metadata, season tabs, episode list with play button.

**Files:**
- Create: `Sources/AetherApp/Views/SeriesDetailView.swift`

```swift
import SwiftUI
import AetherCore

struct SeriesDetailView: View {
    let series: XstreamSeries
    let credentials: XstreamCredentials
    @ObservedObject var player: PlayerCore
    @Environment(\.dismiss) private var dismiss

    @State private var info: XstreamSeriesInfo?
    @State private var isLoading = true
    @State private var selectedSeason: String = "1"

    private let service: XstreamService

    init(series: XstreamSeries, credentials: XstreamCredentials, player: PlayerCore) {
        self.series = series
        self.credentials = credentials
        self.player = player
        self.service = XstreamService(credentials: credentials)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: series.cover.flatMap(URL.init(string:))) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Color.aetherSurface
                    }
                }
                .frame(width: 90, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text(series.name)
                        .font(.aetherTitle)
                        .foregroundStyle(Color.aetherText)
                    if let genre = series.genre {
                        Text(genre)
                            .font(.aetherCaption)
                            .foregroundStyle(.secondary)
                    }
                    if let plot = series.plot {
                        Text(plot)
                            .font(.aetherCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Loading episodes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let info {
                let seasons = info.episodes.keys.sorted { Int($0) ?? 0 < Int($1) ?? 0 }
                Picker("Season", selection: $selectedSeason) {
                    ForEach(seasons, id: \.self) { s in
                        Text("Season \(s)").tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                let episodes = (info.episodes[selectedSeason] ?? [])
                    .sorted { $0.episodeNum < $1.episodeNum }

                List(episodes) { ep in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("E\(ep.episodeNum)  \(ep.title)")
                                .font(.aetherBody)
                                .foregroundStyle(Color.aetherText)
                            if let plot = ep.info?.plot {
                                Text(plot)
                                    .font(.aetherCaption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Button("▶ Play") {
                            playEpisode(ep)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.aetherPrimary)
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    if let first = seasons.first { selectedSeason = first }
                }
            }
        }
        .frame(width: 560, minHeight: 420)
        .background(Color.aetherBackground)
        .task { await loadInfo() }
    }

    private func loadInfo() async {
        isLoading = true
        defer { isLoading = false }
        info = try? await service.seriesInfo(seriesID: series.id)
    }

    private func playEpisode(_ ep: XstreamEpisode) {
        let ext = ep.containerExtension ?? "mp4"
        let url = credentials.baseURL
            .appendingPathComponent("series")
            .appendingPathComponent(credentials.username)
            .appendingPathComponent(credentials.password)
            .appendingPathComponent("\(ep.id).\(ext)")

        let channel = Channel(
            id: UUID(),
            name: "\(series.name) — S\(ep.season)E\(ep.episodeNum) \(ep.title)",
            streamURL: url,
            logoURL: series.cover.flatMap(URL.init(string:)),
            groupTitle: "Series",
            epgId: nil
        )
        player.play(channel)
    }
}
```

**Verify:** `swift build`

---

## Task 4: Wire Series button into PlaylistSidebar / ContentView

**Objective:** Add "Series" toolbar button that opens `SeriesBrowserView` sheet — visible only when the active playlist has Xtream credentials.

**Files:**
- Modify: `Sources/AetherApp/Views/ContentView.swift`

Read `ContentView.swift` first, then add:

1. New `@State private var showSeriesBrowser = false` alongside existing sheet states.
2. In the toolbar, after the existing VOD button (if any) or after the playlist picker, add:

```swift
if let creds = playerCore.currentXstreamCredentials {
    Button {
        showSeriesBrowser = true
    } label: {
        Label("Series", systemImage: "tv.and.mediabox")
    }
    .help("Browse Series")
    .sheet(isPresented: $showSeriesBrowser) {
        SeriesBrowserView(credentials: creds, player: playerCore)
    }
}
```

**Note:** `PlayerCore` does not currently expose `currentXstreamCredentials`. Add a stored property to `PlayerCore`:

```swift
/// Set by PlaylistSidebar when an Xtream playlist is loaded.
public var currentXstreamCredentials: XstreamCredentials?
```

And set it in `PlaylistSidebar` when loading an Xtream playlist.

**Verify:** `swift build`

---

## Task 5: Keyboard shortcut ⌘F — focus channel search

**Objective:** `⌘F` anywhere in the app moves focus to the channel search field in `ChannelListView`.

**Files:**
- Modify: `Sources/AetherApp/Views/ChannelListView.swift`

1. Add `@FocusState private var isSearchFocused: Bool`.
2. Attach `.focused($isSearchFocused)` to the search field (or use `.searchable` with `isPresented` binding if using the searchable modifier).
3. Add keyboard shortcut handler:

```swift
.onKeyPress(.init("f"), modifiers: .command) {
    isSearchFocused = true
    return .handled
}
```

If `ChannelListView` uses `.searchable(text:)` (no explicit TextField), use a `@State private var searchText` + a hidden `TextField` with `.focused()` and `.opacity(0)` approach, or switch to an explicit `TextField` in the toolbar.

**Verify:** `swift build`. Manual test: ⌘F should jump focus to search.

---

## Task 6: Playlist health-check — `PlaylistValidator`

**Objective:** New actor `PlaylistValidator` that pings each channel's stream URL (HEAD request, 3s timeout) and returns a `[Channel: HealthStatus]` dict.

**Files:**
- Create: `Sources/AetherCore/Services/PlaylistValidator.swift`

```swift
import Foundation

public enum HealthStatus: Sendable {
    case ok(Int)        // HTTP status code
    case timeout
    case error(String)
}

public actor PlaylistValidator {

    private let session: URLSession

    public init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 5
        self.session = URLSession(configuration: cfg)
    }

    /// Checks up to `limit` channels concurrently (default 20).
    /// Returns results as an async stream so the UI can update incrementally.
    public func validate(
        channels: [Channel],
        limit: Int = 20
    ) async -> [Channel: HealthStatus] {
        var results: [Channel: HealthStatus] = [:]
        let batch = Array(channels.prefix(limit))

        await withTaskGroup(of: (Channel, HealthStatus).self) { group in
            for channel in batch {
                group.addTask {
                    let status = await self.ping(channel.streamURL)
                    return (channel, status)
                }
            }
            for await (channel, status) in group {
                results[channel] = status
            }
        }
        return results
    }

    private func ping(_ url: URL) async -> HealthStatus {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return .ok(code)
        } catch let err as URLError where err.code == .timedOut {
            return .timeout
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
```

**Verify:** `swift build`

---

## Task 7: PlaylistHealthView — show results in a sheet

**Objective:** Sheet listing channels with colored health indicators (green / yellow / red).

**Files:**
- Create: `Sources/AetherApp/Views/PlaylistHealthView.swift`

```swift
import SwiftUI
import AetherCore

struct PlaylistHealthView: View {
    let channels: [Channel]
    @State private var results: [Channel: HealthStatus] = [:]
    @State private var isRunning = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Playlist Health Check")
                    .font(.aetherTitle)
                    .foregroundStyle(Color.aetherText)
                Spacer()
                if isRunning {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button("Re-check") { Task { await runCheck() } }
                        .buttonStyle(.bordered)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            List(channels) { channel in
                HStack {
                    Circle()
                        .fill(statusColor(for: channel))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name)
                            .font(.aetherBody)
                            .foregroundStyle(Color.aetherText)
                        Text(statusLabel(for: channel))
                            .font(.aetherCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(width: 420, minHeight: 400)
        .background(Color.aetherBackground)
        .task { await runCheck() }
    }

    private func runCheck() async {
        isRunning = true
        defer { isRunning = false }
        let validator = PlaylistValidator()
        results = await validator.validate(channels: channels)
    }

    private func statusColor(for channel: Channel) -> Color {
        switch results[channel] {
        case .ok(let code) where (200..<400).contains(code): return .green
        case .ok: return .yellow
        case .timeout: return .orange
        case .error: return .red
        case nil: return results.isEmpty ? Color.aetherSurface : .gray
        }
    }

    private func statusLabel(for channel: Channel) -> String {
        switch results[channel] {
        case .ok(let code): return "HTTP \(code)"
        case .timeout: return "Timeout"
        case .error(let msg): return msg
        case nil: return results.isEmpty ? "Pending…" : "Skipped"
        }
    }
}
```

Wire into `ChannelListView` toolbar: add `@State private var showHealthCheck = false` and a wrench button that opens the sheet.

**Verify:** `swift build`

---

## Task 8: Unit tests — SRTParser

**Objective:** Test SRT parsing, WebVTT parsing, empty input, and malformed input.

**Files:**
- Modify: `Sources/AetherTests/AetherCoreTests.swift` (or create `Sources/AetherTests/SRTParserTests.swift`)

```swift
import Testing
@testable import AetherCore

@Suite("SRTParser")
struct SRTParserTests {

    @Test("parses basic SRT")
    func basicSRT() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        Hello world

        2
        00:00:05,000 --> 00:00:07,500
        Second cue
        """
        let cues = SRTParser.parse(srt)
        #expect(cues.count == 2)
        #expect(cues[0].text == "Hello world")
        #expect(cues[0].start == 1.0)
        #expect(cues[0].end == 3.0)
        #expect(cues[1].text == "Second cue")
        #expect(abs(cues[1].end - 7.5) < 0.001)
    }

    @Test("parses WebVTT")
    func webVTT() throws {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:02.500
        VTT cue
        """
        let cues = SRTParser.parse(vtt)
        #expect(cues.count == 1)
        #expect(cues[0].text == "VTT cue")
    }

    @Test("empty input returns empty array")
    func emptyInput() {
        #expect(SRTParser.parse("").isEmpty)
    }

    @Test("strips HTML tags from cue text")
    func stripsHTML() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        <i>Italic</i> text
        """
        let cues = SRTParser.parse(srt)
        #expect(cues.first?.text == "Italic text")
    }
}
```

**Verify:** `swift test --filter SRTParserTests` — all pass.

---

## Task 9: Unit tests — BufferingConfig

**Objective:** Verify that `BufferingConfig.apply(to:)` sets the correct values on `AVPlayerItem` and `AVPlayer`.

**Files:**
- Create: `Sources/AetherTests/BufferingConfigTests.swift`

```swift
import Testing
import AVFoundation
@testable import AetherCore

@Suite("BufferingConfig")
struct BufferingConfigTests {

    @Test("apply sets preferredForwardBufferDuration on AVPlayerItem")
    func itemBuffer() {
        let item = AVPlayerItem(url: URL(string: "https://example.com/stream.m3u8")!)
        BufferingConfig.apply(to: item)
        #expect(item.preferredForwardBufferDuration == 30.0)
    }

    @Test("apply sets automaticallyWaitsToMinimizeStalling on AVPlayer")
    func playerNoWait() {
        let player = AVPlayer()
        BufferingConfig.apply(to: player)
        #expect(player.automaticallyWaitsToMinimizeStalling == false)
    }
}
```

**Verify:** `swift test --filter BufferingConfigTests` — all pass.

---

## Task 10: git commit + push + verify CI

**Objective:** Clean commit, push, confirm GitHub Actions green.

```bash
cd /home/hermes/aether
git add -A
git commit -m "feat(sprint12): series browser, playlist health-check, ⌘F search, unit tests

- XstreamService: add XstreamSeries/Episode/SeriesInfo models + 3 API methods
- SeriesBrowserView: category sidebar + series grid (mirrors VODBrowserView)
- SeriesDetailView: season tabs + episode list + play episode
- ContentView: Series toolbar button (visible when Xtream creds available)
- PlayerCore: currentXstreamCredentials stored property
- ChannelListView: ⌘F to focus search
- PlaylistValidator: HEAD-ping actor, 20 concurrent, 3s timeout
- PlaylistHealthView: health-check sheet with colored status indicators
- SRTParserTests: 4 tests (SRT, WebVTT, empty, HTML strip)
- BufferingConfigTests: 2 tests (item buffer duration, player stall wait)"
git push
```

Then poll GitHub Actions API until `conclusion == "success"`.

---

## Summary

| Task | File(s) | Type |
|------|---------|------|
| 1 | XstreamService.swift | Extend existing |
| 2 | SeriesBrowserView.swift | New view |
| 3 | SeriesDetailView.swift | New view |
| 4 | ContentView.swift + PlayerCore.swift | Wire-up |
| 5 | ChannelListView.swift | UX polish |
| 6 | PlaylistValidator.swift | New service |
| 7 | PlaylistHealthView.swift + ChannelListView.swift | New view + wire |
| 8 | SRTParserTests.swift | Unit tests |
| 9 | BufferingConfigTests.swift | Unit tests |
| 10 | git push + CI | Deploy |
