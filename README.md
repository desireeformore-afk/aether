# Aether — IPTV Player for Apple Platforms

A modern, native IPTV player built with Swift 6 and SwiftUI for macOS, iOS, and tvOS.

![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iOS%20%7C%20tvOS-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

### 🎬 Playback
- **Native AVPlayer integration** — hardware-accelerated video decoding
- **M3U & Xtream Codes support** — load playlists from URLs or local files
- **Auto-retry with exponential backoff** — handles unstable streams gracefully
- **Picture-in-Picture** — continue watching while multitasking (macOS/iOS)
- **Sleep timer** — auto-stop playback after a set duration

### 📺 EPG (Electronic Program Guide)
- **XMLTV support** — load EPG data from URLs
- **Now & Next display** — see current and upcoming programs
- **Timeline view** — browse full program schedule
- **Auto-hide overlay** — EPG info appears on hover, hides after 3s

### 🎨 User Interface
- **Fullscreen player** — immersive viewing experience
- **Floating channel panel** — slide-out sidebar with playlists and channels (⌘L)
- **Command Palette** — quick search and navigation (⌘K)
- **Theme engine** — 5 built-in themes + custom gradient builder
- **Favorites** — star channels for quick access
- **Search & filter** — find channels by name or genre

### ⌨️ Keyboard Shortcuts (macOS)
- `Space` — Play/Pause
- `↑` / `↓` — Previous/Next channel
- `M` — Mute/Unmute
- `F` — Add/Remove from Favorites
- `⌘L` — Toggle channel panel
- `⌘K` — Open Command Palette
- `⌘F` — Focus search field
- `⌘,` — Open Settings

### 🎯 Advanced Features
- **Subtitle support** — load SRT files manually or auto-search OpenSubtitles
- **Stream stats** — real-time bitrate, resolution, codec info
- **Watch history** — track viewing sessions with SwiftData
- **Playlist health check** — test stream availability
- **HTTP bypass** — custom URLProtocol for HTTPS streams

---

## Requirements

- **macOS:** 14.0+ (Sonoma)
- **iOS:** 17.0+
- **tvOS:** 17.0+
- **Xcode:** 16.0+ (Swift 6)

---

## Build Instructions

### 1. Clone the repository

```bash
git clone https://github.com/yourusername/aether.git
cd aether
```

### 2. Generate Xcode project

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` file.

```bash
# Install XcodeGen (if not already installed)
brew install xcodegen

# Generate Xcode project
xcodegen generate
```

### 3. Open in Xcode

```bash
open Aether.xcodeproj
```

### 4. Build and run

- Select your target (macOS, iOS, or tvOS)
- Press `⌘R` to build and run

---

## Project Structure

```
aether/
├── Sources/
│   ├── AetherCore/          # Platform-agnostic logic
│   │   ├── Models/          # Channel, Playlist, EPG, Theme
│   │   ├── Services/        # M3U parser, EPG loader, Theme service
│   │   ├── Player/          # PlayerCore (AVPlayer wrapper)
│   │   └── Design/          # Colors, typography
│   ├── AetherUI/            # Shared UI components
│   │   └── Views/           # ThemePickerView, AppearancePickerView
│   ├── AetherApp/           # macOS app
│   │   └── Views/           # PlayerView, ChannelListView, SettingsView
│   ├── AetherAppIOS/        # iOS app
│   └── AetherAppTV/         # tvOS app
├── Tests/
│   └── AetherTests/         # Unit tests
├── project.yml              # XcodeGen configuration
├── CLAUDE.md                # Project instructions for AI assistants
└── PERFORMANCE_REVIEW.md    # Performance analysis
```

---

## Architecture

### Core Principles
- **Swift 6 strict concurrency** — `@MainActor` for UI, `Sendable` for models
- **SwiftData for persistence** — favorites, watch history, playlists
- **AVPlayer for playback** — no third-party video players
- **No force unwraps** — use `guard let` or `if let`

### Key Components

#### PlayerCore
- Wraps `AVPlayer` with `@MainActor` safety
- Handles auto-retry (max 3 attempts with exponential backoff)
- Manages channel navigation (prev/next)
- Tracks watch sessions for history

#### EPGStore
- Loads XMLTV data from URLs
- Provides `nowPlaying()` and `nextUp()` queries
- Caches parsed EPG data in memory

#### ThemeService
- Manages active theme selection
- Persists custom gradients to UserDefaults
- Provides 5 built-in themes (Aether, AMOLED, Nord, Catppuccin, Sunset)

#### ChannelCache
- Persists parsed M3U channels to JSON
- Avoids re-parsing on every launch
- Supports 50,000+ channels efficiently

---

## Testing

Run unit tests:

```bash
swift test
```

Or in Xcode: `⌘U`

---

## Configuration

### Settings (⌘,)

**General:**
- Default stream quality (Auto/High/Medium/Low)
- Hardware decoding toggle

**EPG:**
- Refresh interval (30 min / 1h / 6h / 12h / Never)
- Manual refresh button

**Appearance:**
- Light/Dark/System mode
- Theme picker with custom gradient builder

**Subtitles:**
- Font size, color, background opacity
- OpenSubtitles API key (optional)

**Cache:**
- View cache size
- Clear cache button

---

## Keyboard Shortcuts Reference

| Shortcut | Action |
|----------|--------|
| `Space` | Play/Pause |
| `↑` | Previous channel |
| `↓` | Next channel |
| `M` | Mute/Unmute |
| `F` | Toggle Favorite |
| `⌘L` | Toggle channel panel |
| `⌘K` | Open Command Palette |
| `⌘F` | Focus search |
| `⌘,` | Open Settings |
| `⌘Q` | Quit |

---

## Known Issues

- **Linux build:** Cannot compile on Linux (requires macOS/iOS/tvOS frameworks)
- **HTTP/2 streams:** Some IPTV providers use HTTP/2 which may require additional configuration

---

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- Built with [Swift 6](https://swift.org)
- UI powered by [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- Video playback via [AVFoundation](https://developer.apple.com/av-foundation/)
- Project generation via [XcodeGen](https://github.com/yonaskolb/XcodeGen)

---

## Support

For issues, feature requests, or questions:
- Open an issue on [GitHub](https://github.com/yourusername/aether/issues)
- Check [CLAUDE.md](CLAUDE.md) for development guidelines

---

**Made with ❤️ for IPTV enthusiasts**
