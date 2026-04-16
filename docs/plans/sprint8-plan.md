# Sprint 8 Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Polish & core UX — keyboard shortcuts, watch history, channel grouping, .entitlements fix

**Architecture:** 
- 8a: NSEvent global monitor → PlayerCore keyboard actions
- 8b: WatchHistoryRecord (SwiftData) + "Ostatnio oglądane" in sidebar  
- 8c: Collapsible channel groups by group-title in ChannelListView

**Tech Stack:** Swift 6, SwiftUI, SwiftData, NSEvent, macOS 14+

---

## Task 1: App.entitlements — enable network client (CRITICAL)

**Objective:** Without this, AVPlayer cannot open any network stream in sandboxed macOS app.

**Files:**
- Create: `Sources/AetherApp/Resources/AetherApp.entitlements`
- Modify: `Package.swift` — add entitlements via swiftSettings

**Code:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

Note: SPM doesn't apply entitlements automatically — for SPM-built apps (not Xcode), sandbox is off by default. The entitlements file documents intent and is used if/when the app is code-signed. No Package.swift change needed, just create the file for future reference.

**Commit:** `feat: add App.entitlements for network + sandbox config`

---

## Task 2: WatchHistoryRecord — SwiftData model

**Objective:** Persist watch history (channel + timestamp + duration).

**Files:**
- Create: `Sources/AetherCore/Storage/WatchHistoryRecord.swift`

**Code:**
```swift
import SwiftData
import Foundation

@Model
public final class WatchHistoryRecord {
    public var id: UUID
    public var channelID: String
    public var channelName: String
    public var streamURL: String
    public var logoURL: String?
    public var watchedAt: Date
    public var durationSeconds: Int

    public init(channel: Channel, watchedAt: Date = .now, durationSeconds: Int = 0) {
        self.id = UUID()
        self.channelID = channel.id
        self.channelName = channel.name
        self.streamURL = channel.streamURL.absoluteString
        self.logoURL = channel.logoURL?.absoluteString
        self.watchedAt = watchedAt
        self.durationSeconds = durationSeconds
    }

    public func toChannel() -> Channel {
        Channel(
            id: channelID,
            name: channelName,
            streamURL: URL(string: streamURL)!,
            logoURL: logoURL.flatMap(URL.init),
            group: nil,
            epgID: nil
        )
    }
}
```

**Commit:** `feat: add WatchHistoryRecord SwiftData model`

---

## Task 3: PlayerCore — track watch history

**Objective:** When a channel starts playing, record it. When stopped/switched, save duration.

**Files:**
- Modify: `Sources/AetherCore/Player/PlayerCore.swift`

**Changes:**
- Add `private var watchStartTime: Date?`
- Add `public private(set) var lastWatchedChannel: Channel?`
- In `play(_ channel:)`: save previous channel duration, set `watchStartTime = .now`, post notification via callback
- Add `public var onWatchSessionEnd: ((Channel, Date, Int) -> Void)?` closure — called by AetherApp to save to SwiftData

**Commit:** `feat: PlayerCore tracks watch session start/end`

---

## Task 4: AetherApp — wire WatchHistory to modelContainer + PlayerCore

**Objective:** Register WatchHistoryRecord, save sessions when player switches/stops.

**Files:**
- Modify: `Sources/AetherApp/AetherApp.swift`

**Changes:**
- Add `WatchHistoryRecord.self` to `modelContainer(for:)`
- In `@StateObject playerCore` setup, assign `playerCore.onWatchSessionEnd` closure that inserts `WatchHistoryRecord` into modelContext

**Note:** Use `.task { }` on WindowGroup or a dedicated `HistoryCoordinator` @StateObject that holds modelContext + playerCore reference.

**Commit:** `feat: wire WatchHistoryRecord into AetherApp modelContainer`

---

## Task 5: "Recently Watched" section in PlaylistSidebar

**Objective:** Show last 10 watched channels at the top of the sidebar.

**Files:**
- Modify: `Sources/AetherApp/Views/PlaylistSidebar.swift`

**Changes:**
- Add `@Query(sort: \WatchHistoryRecord.watchedAt, order: .reverse) private var history: [WatchHistoryRecord]`
- Add `import SwiftData`
- Add a `Section("Ostatnio oglądane")` above playlist list, showing up to 5 unique channels
- Tapping a history item calls `playerCore.play(record.toChannel())`

**Commit:** `feat: recently watched section in PlaylistSidebar`

---

## Task 6: Keyboard shortcuts — global NSEvent monitor

**Objective:** space=play/pause, left/right arrow=prev/next channel, m=mute, f=fullscreen, esc=exit fullscreen.

**Files:**
- Create: `Sources/AetherApp/KeyboardShortcutHandler.swift`

**Code:**
```swift
import AppKit
import AetherCore

@MainActor
final class KeyboardShortcutHandler {
    private var monitor: Any?
    private weak var playerCore: PlayerCore?

    init(playerCore: PlayerCore) {
        self.playerCore = playerCore
    }

    func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let player = self.playerCore else { return event }
            switch event.keyCode {
            case 49: // space
                player.togglePlayPause()
                return nil
            case 123: // left arrow
                player.prevChannel()
                return nil
            case 124: // right arrow
                player.nextChannel()
                return nil
            case 46: // m
                player.isMuted.toggle()
                return nil
            default:
                return event
            }
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
```

**Commit:** `feat: KeyboardShortcutHandler — space/arrows/mute`

---

## Task 7: Wire KeyboardShortcutHandler into ContentView

**Objective:** Start/stop keyboard monitoring with the main window lifecycle.

**Files:**
- Modify: `Sources/AetherApp/Views/ContentView.swift`

**Changes:**
- Add `@StateObject` or store handler as private property
- `.onAppear { handler.startMonitoring() }` / `.onDisappear { handler.stopMonitoring() }`

**Commit:** `feat: wire keyboard handler into ContentView`

---

## Task 8: Collapsible channel groups in ChannelListView

**Objective:** Group channels by `group-title`, show collapsible `DisclosureGroup` sections.

**Files:**
- Modify: `Sources/AetherApp/Views/ChannelListView.swift`

**Changes:**
- Replace flat filtered list with `List` of `DisclosureGroup` per unique group
- `@State private var expandedGroups: Set<String> = []`
- Group channels: `Dictionary(grouping: filtered, by: { $0.group ?? "Inne" })`
- Sort groups alphabetically, "Inne" last
- Each group shows channel count badge: `Text("\(channels.count)").foregroundStyle(.secondary)`

**Commit:** `feat: collapsible channel groups by group-title`

---

## Task 9: togglePlayPause() in PlayerCore

**Objective:** PlayerCore is missing `togglePlayPause()` — needed by keyboard handler.

**Files:**
- Modify: `Sources/AetherCore/Player/PlayerCore.swift`

**Changes:**
```swift
public func togglePlayPause() {
    switch state {
    case .playing:
        player.pause()
        state = .paused
    case .paused:
        player.play()
        state = .playing
    default:
        break
    }
}
```

**Commit:** `feat: PlayerCore.togglePlayPause()`

---

## Verification

After all tasks: `git push` → poll CI → green ✅
