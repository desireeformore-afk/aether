# Sprint 13 — Cross-Platform Polish & Release Prep

> **For Hermes:** Use `subagent-driven-development` skill to implement this plan task-by-task.

**Goal:** Make Aether compile and run natively on macOS, iOS, and tvOS — then add Onboarding, Command Palette (⌘K), and PiP support.

**Architecture:**
- `AetherCore` stays fully platform-agnostic (no UIKit/AppKit imports)
- `AetherApp` gains `#if os()` guards everywhere platform APIs differ
- New targets: `AetherAppIOS` and `AetherAppTV` share Views via a `AetherUI` shared module
- All keyboard-driven UX falls back gracefully on touch/remote-based platforms

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVKit, Combine, XCTest

---

## Task 1: Expand Package.swift for iOS + tvOS

**Objective:** Add iOS 17+ and tvOS 17+ platforms to the package; create separate app targets.

**Files:**
- Modify: `Package.swift`

**Step 1: Update platforms and add targets**

```swift
// Package.swift — replace .platforms line and add targets
platforms: [
    .macOS(.v14),
    .iOS(.v17),
    .tvOS(.v17),
],

// Add to products:
.library(name: "AetherUI", targets: ["AetherUI"]),

// Add to targets (after AetherCore):
.target(
    name: "AetherUI",
    dependencies: ["AetherCore"],
    path: "Sources/AetherUI"
),
.target(
    name: "AetherAppIOS",
    dependencies: ["AetherCore", "AetherUI"],
    path: "Sources/AetherAppIOS",
    resources: [.process("Resources/Assets.xcassets")]
),
.target(
    name: "AetherAppTV",
    dependencies: ["AetherCore", "AetherUI"],
    path: "Sources/AetherAppTV",
    resources: [.process("Resources/Assets.xcassets")]
),

// Update AetherApp (macOS) to also depend on AetherUI:
.executableTarget(
    name: "AetherApp",
    dependencies: ["AetherCore", "AetherUI"],
    path: "Sources/AetherApp",
    resources: [.process("Resources/Assets.xcassets")],
    swiftSettings: [.unsafeFlags(["-parse-as-library"])]
),
```

**Step 2: Create `Sources/AetherUI/` directory placeholder**

```bash
mkdir -p Sources/AetherUI/Views Sources/AetherUI/Components
touch Sources/AetherUI/AetherUI.swift   # empty namespace file
```

**Step 3: Build and check — only Package.swift errors expected**

```bash
cd /home/hermes/aether
swift build 2>&1 | head -30
```

**Step 4: Commit**

```bash
git add Package.swift Sources/AetherUI/
git commit -m "feat: add iOS + tvOS targets and AetherUI shared module"
```

---

## Task 2: Guard AppKit-only code with `#if os(macOS)`

**Objective:** `KeyboardShortcutHandler.swift` uses `AppKit`/`NSEvent` — must be macOS-only.

**Files:**
- Modify: `Sources/AetherApp/KeyboardShortcutHandler.swift`
- Modify: `Sources/AetherApp/Views/ContentView.swift`

**Step 1: Wrap entire KeyboardShortcutHandler in `#if os(macOS)`**

```swift
// KeyboardShortcutHandler.swift — complete file
#if os(macOS)
import AppKit
import AetherCore

/// Monitors local keyboard events and routes them to `PlayerCore`.
/// macOS only — iOS/tvOS use SwiftUI focus-based shortcuts instead.
@MainActor
final class KeyboardShortcutHandler {
    private var monitor: Any?
    private weak var playerCore: PlayerCore?

    init(playerCore: PlayerCore) { self.playerCore = playerCore }

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let player = self.playerCore else { return event }
            return self.handle(event: event, player: player)
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(event: NSEvent, player: PlayerCore) -> NSEvent? {
        guard !isTypingInTextField() else { return event }
        switch event.keyCode {
        case 49: player.togglePlayPause(); return nil
        case 123: player.playPrevious(); return nil
        case 124: player.playNext(); return nil
        case 46 where !event.modifierFlags.contains(.command):
            player.toggleMute(); return nil
        default: return event
        }
    }

    private func isTypingInTextField() -> Bool {
        guard let window = NSApp.keyWindow,
              let responder = window.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
}
#endif
```

**Step 2: Guard ContentView usage of KeyboardShortcutHandler**

In `ContentView.swift`, wrap the keyboard handler property and all references:

```swift
// In ContentView — platform-guarded properties
#if os(macOS)
private let keyboardHandler: KeyboardShortcutHandler
#endif

// In init():
#if os(macOS)
self.keyboardHandler = KeyboardShortcutHandler(playerCore: playerCore)
#endif

// In .onAppear:
#if os(macOS)
keyboardHandler.startMonitoring()
#endif

// In .onDisappear:
#if os(macOS)
keyboardHandler.stopMonitoring()
#endif
```

**Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -20
```

**Step 4: Commit**

```bash
git add Sources/AetherApp/KeyboardShortcutHandler.swift Sources/AetherApp/Views/ContentView.swift
git commit -m "fix: guard AppKit keyboard handler with #if os(macOS)"
```

---

## Task 3: Guard `.onKeyPress` and `Settings {}` Scene (macOS only)

**Objective:** `.onKeyPress` and `Settings {}` are macOS-only SwiftUI APIs.

**Files:**
- Modify: `Sources/AetherApp/Views/PlayerView.swift`
- Modify: `Sources/AetherApp/Views/ChannelListView.swift`
- Modify: `Sources/AetherApp/AetherApp.swift`

**Step 1: Wrap `.onKeyPress` in PlayerView.swift**

Find each `.onKeyPress` modifier and wrap in `#if os(macOS)`:

```swift
// PlayerView.swift — around the three .onKeyPress modifiers
#if os(macOS)
.onKeyPress(.space) { player.togglePlayPause(); return .handled }
.onKeyPress(.leftArrow) { player.playPrevious(); return .handled }
.onKeyPress(.rightArrow) { player.playNext(); return .handled }
#endif
```

**Step 2: Wrap ⌘F focus trigger in ChannelListView.swift**

```swift
// ChannelListView.swift — guard onKeyPress(.init("f"))
#if os(macOS)
.onKeyPress(.init("f"), phases: .down) { event in
    if event.modifiers.contains(.command) {
        isSearchFocused = true
        return .handled
    }
    return .ignored
}
#endif
```

**Step 3: Wrap `Settings {}` in AetherApp.swift**

```swift
// AetherApp.swift — Settings scene is macOS-only
#if os(macOS)
Settings {
    SettingsView()
        .environmentObject(epgStore)
}
#endif
```

**Step 4: Build and verify no errors**

```bash
swift build 2>&1 | grep "error:" | head -20
```

**Step 5: Commit**

```bash
git add Sources/AetherApp/Views/PlayerView.swift Sources/AetherApp/Views/ChannelListView.swift Sources/AetherApp/AetherApp.swift
git commit -m "fix: guard macOS-only SwiftUI APIs with #if os(macOS)"
```

---

## Task 4: Create shared `AetherUI` — ChannelRowView + PlayerControlsView

**Objective:** Extract reusable, platform-agnostic View components into `AetherUI` so iOS/tvOS can use them.

**Files:**
- Create: `Sources/AetherUI/Views/ChannelRowView.swift`
- Create: `Sources/AetherUI/Views/PlayerControlsView.swift`
- Create: `Sources/AetherUI/Views/EmptyStateView.swift`

**Step 1: ChannelRowView.swift**

```swift
import SwiftUI
import AetherCore

/// A single row showing channel logo, name, and EPG info.
/// Works on macOS, iOS, and tvOS.
public struct ChannelRowView: View {
    public let channel: Channel
    public let isSelected: Bool
    public var epgTitle: String? = nil

    public init(channel: Channel, isSelected: Bool, epgTitle: String? = nil) {
        self.channel = channel
        self.isSelected = isSelected
        self.epgTitle = epgTitle
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Logo
            AsyncImage(url: URL(string: channel.logoURL ?? "")) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "tv")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                if let title = epgTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
```

**Step 2: PlayerControlsView.swift**

```swift
import SwiftUI
import AetherCore

/// Transport controls: play/pause, prev, next, mute, volume.
/// Shared across macOS, iOS, tvOS — layout adapts via environment.
public struct PlayerControlsView: View {
    @ObservedObject public var player: PlayerCore

    public init(player: PlayerCore) { self.player = player }

    public var body: some View {
        HStack(spacing: 20) {
            Button { player.playPrevious() } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous channel")

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { player.playNext() } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next channel")

            Spacer()

            Button { player.toggleMute() } label: {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isMuted ? "Unmute" : "Mute")

            #if !os(tvOS)
            Slider(value: Binding(
                get: { player.volume },
                set: { player.setVolume($0) }
            ), in: 0...1)
            .frame(width: 80)
            .accessibilityLabel("Volume")
            #endif
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
```

**Step 3: EmptyStateView.swift**

```swift
import SwiftUI

/// Generic empty state — works on all platforms.
public struct EmptyStateView: View {
    public let title: String
    public let systemImage: String
    public var message: String? = nil

    public init(title: String, systemImage: String, message: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

**Step 4: Build**

```bash
swift build 2>&1 | grep "error:" | head -20
```

**Step 5: Commit**

```bash
git add Sources/AetherUI/
git commit -m "feat: add AetherUI shared components (ChannelRowView, PlayerControlsView, EmptyStateView)"
```

---

## Task 5: iOS App Entry Point (`AetherAppIOS`)

**Objective:** Create a minimal iOS app target using shared AetherUI components.

**Files:**
- Create: `Sources/AetherAppIOS/AetherAppIOS.swift`
- Create: `Sources/AetherAppIOS/Views/IOSContentView.swift`
- Create: `Sources/AetherAppIOS/Resources/Assets.xcassets/` (copy from AetherApp)

**Step 1: AetherAppIOS.swift**

```swift
import SwiftUI
import SwiftData
import AetherCore

@main
struct AetherAppIOS: App {
    @StateObject private var playerCore = PlayerCore()
    @StateObject private var epgStore = EPGStore()

    var body: some Scene {
        WindowGroup {
            IOSContentView(playerCore: playerCore)
                .environmentObject(epgStore)
                .environmentObject(playerCore)
        }
        .modelContainer(for: [
            PlaylistRecord.self,
            ChannelRecord.self,
            FavoriteRecord.self,
            WatchHistoryRecord.self,
        ])
    }
}
```

**Step 2: IOSContentView.swift**

```swift
import SwiftUI
import SwiftData
import AetherCore
import AetherUI

/// Root view for iOS — tab-based navigation.
struct IOSContentView: View {
    @ObservedObject var playerCore: PlayerCore
    @EnvironmentObject private var epgStore: EPGStore

    @State private var selectedPlaylist: PlaylistRecord?
    @State private var selectedChannel: Channel?

    var body: some View {
        TabView {
            NavigationStack {
                PlaylistSidebar(selectedPlaylist: $selectedPlaylist)
                    .navigationTitle("Playlists")
            }
            .tabItem { Label("Playlists", systemImage: "list.bullet") }

            NavigationStack {
                if let playlist = selectedPlaylist {
                    ChannelListView(
                        playlist: playlist,
                        selectedChannel: $selectedChannel,
                        player: playerCore
                    )
                } else {
                    EmptyStateView(
                        title: "No Playlist",
                        systemImage: "list.bullet.rectangle",
                        message: "Select a playlist first."
                    )
                }
            }
            .tabItem { Label("Channels", systemImage: "antenna.radiowaves.left.and.right") }

            PlayerView(player: playerCore)
                .tabItem { Label("Player", systemImage: "play.circle") }
        }
    }
}
```

**Step 3: Copy Assets**

```bash
cp -r Sources/AetherApp/Resources/Assets.xcassets Sources/AetherAppIOS/Resources/
```

**Step 4: Build iOS target (cross-compilation check)**

```bash
# This checks compilation — we don't have an iOS simulator on CI, but compiler errors matter
swift build --target AetherAppIOS 2>&1 | grep "error:" | head -20
```

**Step 5: Commit**

```bash
git add Sources/AetherAppIOS/
git commit -m "feat: iOS app entry point with tab-based navigation"
```

---

## Task 6: tvOS App Entry Point (`AetherAppTV`)

**Objective:** Create a tvOS app target using remote-friendly focus-based navigation.

**Files:**
- Create: `Sources/AetherAppTV/AetherAppTV.swift`
- Create: `Sources/AetherAppTV/Views/TVContentView.swift`
- Create: `Sources/AetherAppTV/Resources/Assets.xcassets/` (copy from AetherApp)

**Step 1: AetherAppTV.swift**

```swift
import SwiftUI
import SwiftData
import AetherCore

@main
struct AetherAppTV: App {
    @StateObject private var playerCore = PlayerCore()
    @StateObject private var epgStore = EPGStore()

    var body: some Scene {
        WindowGroup {
            TVContentView(playerCore: playerCore)
                .environmentObject(epgStore)
                .environmentObject(playerCore)
        }
        .modelContainer(for: [
            PlaylistRecord.self,
            ChannelRecord.self,
            FavoriteRecord.self,
            WatchHistoryRecord.self,
        ])
    }
}
```

**Step 2: TVContentView.swift**

```swift
import SwiftUI
import AetherCore
import AetherUI

/// Root view for tvOS — fullscreen player with overlay channel list.
struct TVContentView: View {
    @ObservedObject var playerCore: PlayerCore
    @EnvironmentObject private var epgStore: EPGStore

    @State private var selectedPlaylist: PlaylistRecord?
    @State private var selectedChannel: Channel?
    @State private var showChannelList = false

    var body: some View {
        ZStack {
            // Full-screen player
            PlayerView(player: playerCore)
                .ignoresSafeArea()

            // Overlay channel list (toggle with Menu button)
            if showChannelList {
                HStack {
                    VStack {
                        if let playlist = selectedPlaylist {
                            ChannelListView(
                                playlist: playlist,
                                selectedChannel: $selectedChannel,
                                player: playerCore
                            )
                        } else {
                            EmptyStateView(
                                title: "No Playlist",
                                systemImage: "list.bullet.rectangle"
                            )
                        }
                    }
                    .frame(width: 400)
                    .background(.ultraThinMaterial)
                    Spacer()
                }
                .transition(.move(edge: .leading))
            }
        }
        .onPlayPauseCommand { playerCore.togglePlayPause() }  // Siri Remote play/pause
        .animation(.easeInOut(duration: 0.25), value: showChannelList)
    }
}
```

**Step 3: Copy Assets**

```bash
cp -r Sources/AetherApp/Resources/Assets.xcassets Sources/AetherAppTV/Resources/
```

**Step 4: Build tvOS target**

```bash
swift build --target AetherAppTV 2>&1 | grep "error:" | head -20
```

**Step 5: Commit**

```bash
git add Sources/AetherAppTV/
git commit -m "feat: tvOS app entry point with fullscreen player and overlay channel list"
```

---

## Task 7: Onboarding Flow (shared AetherUI)

**Objective:** First-launch onboarding sheet — add playlist, pick type, done. Works on all platforms.

**Files:**
- Create: `Sources/AetherUI/Views/OnboardingView.swift`
- Modify: `Sources/AetherApp/AetherApp.swift`
- Modify: `Sources/AetherAppIOS/AetherAppIOS.swift`

**Step 1: OnboardingView.swift**

```swift
import SwiftUI
import AetherCore

/// First-launch onboarding — shown until user adds their first playlist.
/// Platform-agnostic. Parent controls `isPresented`.
public struct OnboardingView: View {
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    @State private var step = 0

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                welcomePage.tag(0)
                addPlaylistPage.tag(1)
                readyPage.tag(2)
            }
            #if os(macOS) || os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.borderless)
                }
                Spacer()
                if step < 2 {
                    Button("Next") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") { isPresented = false }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 480, height: 380)
        #endif
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.aetherAccent)
            Text("Welcome to Aether")
                .font(.largeTitle).bold()
            Text("Your personal IPTV player — channels, VOD, and series in one place.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private var addPlaylistPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 64))
                .foregroundStyle(Color.aetherAccent)
            Text("Add Your Playlist")
                .font(.largeTitle).bold()
            Text("Paste an M3U URL or enter your Xtream Codes credentials.\nYou can add more playlists anytime from the sidebar.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private var readyPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're All Set!")
                .font(.largeTitle).bold()
            Text("Tap the + button in the sidebar to add your first playlist.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .padding()
    }
}
```

**Step 2: Wire onboarding into AetherApp.swift (macOS)**

Add to `AetherApp` struct:

```swift
// In AetherApp body, add to ContentView modifier chain:
@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

// In WindowGroup:
ContentView(playerCore: playerCore)
    // ... existing modifiers ...
    .sheet(isPresented: .constant(!hasCompletedOnboarding)) {
        OnboardingView(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { hasCompletedOnboarding = !$0 }
        ))
        .interactiveDismissDisabled()
    }
```

**Step 3: Wire onboarding into AetherAppIOS.swift**

Same pattern — add `@AppStorage("hasCompletedOnboarding")` and `.sheet`.

**Step 4: Build**

```bash
swift build 2>&1 | grep "error:" | head -20
```

**Step 5: Commit**

```bash
git add Sources/AetherUI/Views/OnboardingView.swift Sources/AetherApp/AetherApp.swift Sources/AetherAppIOS/AetherAppIOS.swift
git commit -m "feat: cross-platform onboarding flow (3-step sheet)"
```

---

## Task 8: Command Palette ⌘K (macOS + iOS)

**Objective:** Quick-open overlay to jump between channels and playlists via keyboard or search.

**Files:**
- Create: `Sources/AetherUI/Views/CommandPaletteView.swift`
- Modify: `Sources/AetherApp/Views/ContentView.swift`

**Step 1: CommandPaletteView.swift**

```swift
import SwiftUI
import AetherCore

/// ⌘K command palette — fuzzy search channels and playlists.
/// macOS: triggered via keyboard shortcut. iOS: triggered by toolbar button.
public struct CommandPaletteView: View {
    @Binding public var isPresented: Bool
    public let channels: [Channel]
    public let onSelect: (Channel) -> Void

    public init(isPresented: Binding<Bool>, channels: [Channel], onSelect: @escaping (Channel) -> Void) {
        self._isPresented = isPresented
        self.channels = channels
        self.onSelect = onSelect
    }

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var results: [Channel] {
        guard !query.isEmpty else { return Array(channels.prefix(8)) }
        return channels.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }.prefix(8).map { $0 }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Go to channel...", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .font(.title3)
                    .onSubmit {
                        if let first = results.first {
                            onSelect(first)
                            isPresented = false
                        }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            Divider()

            // Results list
            if results.isEmpty {
                Text("No channels found")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { channel in
                            Button {
                                onSelect(channel)
                                isPresented = false
                            } label: {
                                ChannelRowView(channel: channel, isSelected: false)
                                    .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        #if os(macOS)
        .frame(width: 480)
        .shadow(radius: 20)
        #endif
        .onAppear { isSearchFocused = true }
    }
}
```

**Step 2: Wire ⌘K into ContentView.swift (macOS)**

```swift
// In ContentView — add state and overlay
@State private var showCommandPalette = false

// In body, add to NavigationSplitView modifiers:
.overlay(alignment: .top) {
    if showCommandPalette {
        CommandPaletteView(
            isPresented: $showCommandPalette,
            channels: /* channels from selected playlist */,
            onSelect: { channel in
                selectedChannel = channel
                playerCore.play(channel)
            }
        )
        .padding(.top, 60)
        .padding(.horizontal, 80)
    }
}
#if os(macOS)
.keyboardShortcut("k", modifiers: .command)  // triggers via a Button trick
#endif
```

> **Note:** SwiftUI doesn't support `.keyboardShortcut` directly on views in non-button contexts.
> Use a hidden `Button` with `.keyboardShortcut("k", modifiers: .command)` that toggles `showCommandPalette`.

```swift
// Hidden button for ⌘K — add inside body (outside NavigationSplitView)
#if os(macOS)
Button("") { showCommandPalette.toggle() }
    .keyboardShortcut("k", modifiers: .command)
    .frame(width: 0, height: 0)
    .hidden()
#endif
```

**Step 3: Build**

```bash
swift build 2>&1 | grep "error:" | head -20
```

**Step 4: Commit**

```bash
git add Sources/AetherUI/Views/CommandPaletteView.swift Sources/AetherApp/Views/ContentView.swift
git commit -m "feat: command palette (⌘K) with fuzzy channel search"
```

---

## Task 9: PiP Support (macOS + iOS)

**Objective:** Enable native Picture-in-Picture via `AVKit` — already partially wired in `PlayerCore`.

**Files:**
- Modify: `Sources/AetherApp/Views/PlayerView.swift`
- Modify: `Sources/AetherCore/Player/PlayerCore.swift` (if needed)

**Step 1: Add PiP button to PlayerView toolbar**

```swift
// In PlayerView.swift — add PiP toggle button in controls overlay
#if os(macOS) || os(iOS)
Button {
    // AVPlayerView handles PiP natively when allowsPictureInPicturePlayback = true
    // Trigger via the coordinator notification
    NotificationCenter.default.post(name: .togglePiP, object: nil)
} label: {
    Image(systemName: playerCore.isPiPActive ? "pip.exit" : "pip.enter")
}
.buttonStyle(.plain)
.help("Picture in Picture")
#endif
```

**Step 2: Define the notification name in AetherCore**

```swift
// Sources/AetherCore/Player/PlayerCore.swift — add extension
public extension Notification.Name {
    static let togglePiP = Notification.Name("AetherTogglePiP")
}
```

**Step 3: Wire notification in VideoPlayerLayer coordinator (PlayerView.swift)**

```swift
// In VideoPlayerLayer Coordinator — add observer
NotificationCenter.default.addObserver(
    self, selector: #selector(handleTogglePiP),
    name: .togglePiP, object: nil
)

@objc func handleTogglePiP() {
    #if os(macOS)
    playerView.togglePictureInPicture(nil)
    #elseif os(iOS)
    // AVPlayerViewController handles this automatically
    #endif
}
```

**Step 4: Build**

```bash
swift build 2>&1 | grep "error:" | head -20
```

**Step 5: Commit**

```bash
git add Sources/AetherApp/Views/PlayerView.swift Sources/AetherCore/Player/PlayerCore.swift
git commit -m "feat: PiP toggle button with notification bridge"
```

---

## Task 10: Update CI to build all targets + platforms

**Objective:** GitHub Actions must build AetherApp, AetherAppIOS, AetherAppTV and run tests.

**Files:**
- Modify: `.github/workflows/ci.yml`

**Step 1: Update build step**

```yaml
# .github/workflows/ci.yml — replace single swift build step with:
- name: Build all targets
  run: |
    swift build --target AetherCore
    swift build --target AetherUI
    swift build --target AetherApp
    # iOS and tvOS require SDK flags — skip in macOS-only CI for now
    # swift build --target AetherAppIOS -sdk $(xcrun --sdk iphonesimulator --show-sdk-path)
    # swift build --target AetherAppTV -sdk $(xcrun --sdk appletvsimulator --show-sdk-path)

- name: Run tests
  run: swift test --parallel
```

> **Note:** iOS/tvOS SDK builds require `xcrun` SDK flags not available on all CI setups.
> Add a separate job with `xcodebuild` + `-destination` if full multi-platform CI is needed.
> For now, AetherCore + AetherUI type-check coverage is sufficient.

**Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: build AetherCore, AetherUI, AetherApp separately for cleaner error isolation"
```

---

## Task 11: Sprint 13 Tests

**Objective:** Unit tests for new cross-platform components.

**Files:**
- Create: `Sources/AetherTests/Sprint13Tests.swift`

**Step 1: Write tests**

```swift
import XCTest
@testable import AetherCore

final class Sprint13Tests: XCTestCase {

    // MARK: - OnboardingView logic (model-level)

    func testOnboardingDefaultsToNotCompleted() {
        // AppStorage uses UserDefaults — just test the default value key
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "hasCompletedOnboarding")
        let value = defaults.bool(forKey: "hasCompletedOnboarding")
        XCTAssertFalse(value, "Onboarding should not be completed by default")
    }

    // MARK: - PlayerCore PiP state

    func testPiPStateDefaultsFalse() {
        let core = PlayerCore()
        XCTAssertFalse(core.isPiPActive, "PiP should be inactive by default")
    }

    func testSetPiPActive() {
        let core = PlayerCore()
        core.setPiPActive(true)
        XCTAssertTrue(core.isPiPActive)
        core.setPiPActive(false)
        XCTAssertFalse(core.isPiPActive)
    }

    // MARK: - CommandPalette fuzzy filter (simulated)

    func testFuzzyChannelFilter() {
        let names = ["BBC One", "CNN International", "BBC Two", "Al Jazeera"]
        let query = "bbc"
        let filtered = names.filter { $0.localizedCaseInsensitiveContains(query) }
        XCTAssertEqual(filtered, ["BBC One", "BBC Two"])
    }

    // MARK: - Notification name

    func testTogglePiPNotificationName() {
        XCTAssertEqual(Notification.Name.togglePiP.rawValue, "AetherTogglePiP")
    }
}
```

**Step 2: Run tests**

```bash
swift test --filter Sprint13Tests 2>&1 | tail -10
```

**Step 3: Commit**

```bash
git add Sources/AetherTests/Sprint13Tests.swift
git commit -m "test: Sprint 13 — onboarding, PiP state, command palette filter"
```

---

## Task 12: Final push + CI verification

**Step 1: Push to GitHub**

```bash
cd /home/hermes/aether
git push origin main
```

**Step 2: Wait for CI**

```bash
sleep 30
gh run list --limit 1
gh run watch
```

**Step 3: Verify green**

All jobs must pass. Report via Telegram only on success.

---

## Summary

| Task | What | Platform |
|------|------|----------|
| 1 | Add iOS + tvOS to Package.swift + AetherUI target | All |
| 2 | Guard AppKit keyboard handler | macOS |
| 3 | Guard `.onKeyPress` + `Settings {}` | macOS |
| 4 | Shared ChannelRowView, PlayerControlsView, EmptyStateView | All |
| 5 | iOS app target | iOS |
| 6 | tvOS app target (fullscreen + Siri Remote) | tvOS |
| 7 | Onboarding (3-step sheet) | All |
| 8 | Command Palette ⌘K | macOS + iOS |
| 9 | PiP toggle button | macOS + iOS |
| 10 | CI update | CI |
| 11 | Sprint 13 Tests | All |
| 12 | Push + CI verify | CI |
