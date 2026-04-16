# Aether — IPTV Player for macOS

## Stack
- Swift 6, SwiftUI, AVPlayer, SwiftData
- macOS 14+ (Sonoma)
- SPM (no Xcode project)

## Architecture
- `AetherCore` — models, parsers, services, storage (platform-agnostic logic)
- `AetherApp` — SwiftUI app, views, navigation

## Coding Rules
- Swift 6 strict concurrency — use `async/await`, `@MainActor` where needed
- SwiftData for persistence — no CoreData
- AVPlayer for all playback — no third-party players
- No force unwraps (`!`) — use `guard let` or `if let`
- Errors: use typed `enum` conforming to `Error`, never `fatalError` in production code

## Key Models (to be created in AetherCore)
- `Channel` — name, logoURL, streamURL, groupTitle, epgId
- `Category` — name, channels
- `Playlist` — name, url, type (m3u/xstream), credentials
- `EPGProgram` — channelId, title, start, end, description

## Testing
- Unit tests in `AetherTests`
- Test M3U parser with edge cases (no header, BOM, CRLF, missing attributes)
- Run: `swift test`
