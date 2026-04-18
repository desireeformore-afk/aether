# Aether User Guide

Welcome to Aether, a modern IPTV player for macOS built with SwiftUI and AVFoundation.

## Table of Contents

- [Getting Started](#getting-started)
- [Adding Playlists](#adding-playlists)
- [Playing Channels](#playing-channels)
- [Features](#features)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Troubleshooting](#troubleshooting)

## Getting Started

### System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

### First Launch

1. Launch Aether from your Applications folder
2. The app will open with an empty playlist sidebar
3. Add your first playlist to get started

## Adding Playlists

Aether supports two types of playlists:

### M3U/M3U8 Playlists

1. Click the **+** button in the sidebar
2. Select **Add M3U Playlist**
3. Enter a name for your playlist
4. Provide the M3U URL or select a local file
5. (Optional) Add an EPG URL for program guide data
6. Click **Add**

### Xtream Codes API

1. Click the **+** button in the sidebar
2. Select **Add Xtream Playlist**
3. Enter a name for your playlist
4. Provide your Xtream server URL, username, and password
5. Click **Add**

The playlist will automatically load and display channels grouped by category.

## Playing Channels

### Basic Playback

1. Select a playlist from the sidebar
2. Browse channels in the middle column
3. Click a channel to start playback
4. Use the player controls at the bottom to:
   - Play/Pause (Space)
   - Stop playback
   - Navigate to previous/next channel (← →)
   - Adjust volume
   - Mute/unmute (M)

### Channel Navigation

- **Search**: Use ⌘F or click the search field to filter channels
- **Groups**: Click category chips to filter by group
- **Favorites**: Click the star icon to add channels to favorites
- **Collapse Groups**: Click group headers to collapse/expand sections

### Favorites Tab

Switch to the Favorites tab to see your starred channels:
- Star channels from the All tab or player controls
- Swipe to delete favorites
- Favorites persist across app launches

## Features

### Picture-in-Picture (PiP)

Watch channels in a floating window while using other apps:
- Click the PiP button in player controls (or press P)
- The video floats above other windows
- Click to return to the main window

### EPG (Electronic Program Guide)

When an EPG URL is configured:
- Current program displays in the player
- Progress bar shows program timeline
- Click the calendar icon to view the full schedule
- See what's playing now and coming up next

### Sleep Timer

Auto-stop playback after a set duration:
1. Click the moon icon in player controls
2. Select a duration (15m, 30m, 1h, 2h)
3. Timer counts down and fades out audio
4. Click again to cancel or adjust

### Stream Quality

Control bandwidth usage:
1. Click the quality selector in player controls
2. Choose from Auto, High (4 Mbps), Medium (1.5 Mbps), or Low (500 kbps)
3. Auto adapts to your connection speed
4. View current quality in stream stats

### Stream Statistics

Monitor playback performance:
- Click the chart icon to show/hide stats
- View current quality, bitrate, dropped frames, and buffer
- Useful for diagnosing playback issues

### Subtitles

Search and load subtitles from OpenSubtitles:
1. Click the captions button in player controls
2. Wait for subtitle search to complete
3. Select a subtitle track
4. Subtitles display as an overlay
5. Click "Clear subtitles" to remove

### Playlist Import/Export

**Export**: Settings → Playlists → Export Playlist to M3U
- Saves current channels to an M3U file
- Preserves logos, EPG IDs, and groups

**Import**: Settings → Playlists → Import M3U File
- Adds channels from an M3U file
- Merges with existing channels

### Themes

Customize the app appearance:
1. Open Settings (⌘,)
2. Go to Appearance tab
3. Choose from multiple color themes
4. Select light, dark, or system appearance

## Keyboard Shortcuts

### Playback
- **Space**: Play/Pause
- **←**: Previous channel
- **→**: Next channel
- **M**: Mute/Unmute
- **P**: Toggle Picture-in-Picture
- **F**: Add/Remove from Favorites

### Navigation
- **⌘F**: Focus search field
- **⌘,**: Open Settings
- **⌘W**: Close window
- **⌘Q**: Quit app

## Troubleshooting

### Channel Won't Play

1. Check your internet connection
2. Verify the stream URL is valid
3. Try a different quality setting
4. Check stream stats for errors
5. Some streams may be geo-restricted

### EPG Not Loading

1. Verify the EPG URL is correct
2. Check Settings → EPG → Status for errors
3. Click "Refresh Now" to force reload
4. EPG data may take time to download

### Playback Stuttering

1. Lower the quality setting
2. Check stream stats for dropped frames
3. Close other bandwidth-intensive apps
4. Try a wired connection instead of Wi-Fi

### Subtitles Not Appearing

1. Ensure the channel is playing
2. Wait for subtitle search to complete
3. Try selecting a different subtitle track
4. Some channels may not have subtitles available

### App Performance

For large playlists (1000+ channels):
- Use the search function to filter
- Collapse unused groups
- The app loads channels in batches of 100
- Click "Load More Channels" to see additional channels

## Settings

Access Settings via **Aether → Settings** or **⌘,**

### General
- Default stream quality
- Hardware decoding (recommended for Apple Silicon)

### Playlists
- Import/Export M3U files

### EPG
- Auto-refresh interval
- Manual refresh
- Cache management

### Cache
- View cache size
- Clear EPG cache
- Clear logo cache

### Subtitles
- OpenSubtitles API configuration
- Language preferences

### Appearance
- Theme selection
- Light/Dark/System mode

## Tips & Tricks

1. **Quick Channel Switch**: Use ← → keys to zap through channels
2. **Batch Loading**: Large playlists load 100 channels at a time for better performance
3. **Favorites Workflow**: Star channels as you discover them, then use the Favorites tab
4. **EPG Timeline**: Click the calendar button to see the full day's schedule
5. **PiP + Favorites**: Use PiP to watch while browsing other channels
6. **Search Tips**: Search works across channel names in real-time
7. **Group Filtering**: Click a group chip to see only channels in that category
8. **Sleep Timer**: Perfect for falling asleep to your favorite channel

## Support

For issues, feature requests, or contributions:
- GitHub: https://github.com/desireeformore-afk/aether
- Report bugs via GitHub Issues

---

**Version**: 1.0  
**Last Updated**: 2025
