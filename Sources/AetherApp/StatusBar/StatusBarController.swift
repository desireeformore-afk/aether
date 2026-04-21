import AppKit
import SwiftUI
import Combine
import AetherCore
import SwiftData

/// macOS Menu Bar widget that shows "Now Playing" info and provides quick access to favorite channels.
@MainActor
@Observable
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let player: PlayerCore
    private var cancellables = Set<AnyCancellable>()
    private var modelContainer: ModelContainer?
    private var favorites: [FavoriteRecord] = []
    private var logoImageCache: [UUID: NSImage] = [:]

    init(player: PlayerCore) {
        self.player = player
        setupModelContainer()
    }

    private func setupModelContainer() {
        modelContainer = AetherApp.sharedModelContainer
        loadFavorites()
    }

    private func loadFavorites() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<FavoriteRecord>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        favorites = (try? context.fetch(descriptor)) ?? []
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "Aether")
            button.imagePosition = .imageLeading
        }

        updateMenu()
        observePlayer()

        // Reload favorites periodically to catch changes
        Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.loadFavorites()
                self?.updateMenu()
            }
            .store(in: &cancellables)
    }

    func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        cancellables.removeAll()
    }

    private func observePlayer() {
        // Observe state changes using withObservationTracking
        Task { @MainActor in
            while !Task.isCancelled {
                withObservationTracking {
                    _ = player.currentChannel
                    _ = player.state
                } onChange: {
                    Task { @MainActor in
                        self.updateMenu()
                        self.updateButtonTitle()
                    }
                }
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }

    private func updateButtonTitle() {
        guard let button = statusItem?.button else { return }

        if let channel = player.currentChannel, player.state == .playing {
            button.title = " \(channel.name)"

            // Load and display channel logo if available
            if let logoURL = channel.logoURL {
                loadChannelLogo(for: channel.id, from: logoURL) { [weak self] image in
                    guard let self, let button = self.statusItem?.button else { return }
                    button.image = image
                    button.imagePosition = .imageLeading
                }
            } else {
                button.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "Aether")
            }
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "Aether")
        }
    }

    private func loadChannelLogo(for channelID: UUID, from url: URL, completion: @escaping (NSImage) -> Void) {
        // Check cache first
        if let cached = logoImageCache[channelID] {
            completion(cached)
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) {
                    // Resize to menu bar size
                    let resized = resizeImage(image, to: NSSize(width: 18, height: 18))
                    await MainActor.run {
                        logoImageCache[channelID] = resized
                        completion(resized)
                    }
                }
            } catch {
                // Silently fail and keep default icon
            }
        }
    }

    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    private func updateMenu() {
        guard let item = statusItem else { return }

        let menu = NSMenu()

        // Now Playing section
        if let channel = player.currentChannel {
            let nowPlayingItem = NSMenuItem(
                title: "▶︎ \(channel.name)",
                action: nil,
                keyEquivalent: ""
            )
            nowPlayingItem.isEnabled = false
            menu.addItem(nowPlayingItem)

            menu.addItem(NSMenuItem.separator())

            // Playback controls
            let playPauseTitle = player.state == .playing ? "Pause" : "Play"
            let playPauseIcon = player.state == .playing ? "⏸" : "▶︎"
            let playPauseItem = NSMenuItem(
                title: "\(playPauseIcon) \(playPauseTitle)",
                action: #selector(togglePlayPause),
                keyEquivalent: " "
            )
            playPauseItem.target = self
            menu.addItem(playPauseItem)

            let stopItem = NSMenuItem(
                title: "⏹ Stop",
                action: #selector(stopPlayback),
                keyEquivalent: ""
            )
            stopItem.target = self
            menu.addItem(stopItem)

            menu.addItem(NSMenuItem.separator())

            // Next/Previous controls
            let prevItem = NSMenuItem(
                title: "⏮ Previous Channel",
                action: #selector(playPrevious),
                keyEquivalent: "["
            )
            prevItem.target = self
            menu.addItem(prevItem)

            let nextItem = NSMenuItem(
                title: "⏭ Next Channel",
                action: #selector(playNext),
                keyEquivalent: "]"
            )
            nextItem.target = self
            menu.addItem(nextItem)

            menu.addItem(NSMenuItem.separator())

            // Volume controls
            let muteTitle = player.isMuted ? "Unmute" : "Mute"
            let muteIcon = player.isMuted ? "🔇" : "🔊"
            let muteItem = NSMenuItem(
                title: "\(muteIcon) \(muteTitle)",
                action: #selector(toggleMute),
                keyEquivalent: "m"
            )
            muteItem.target = self
            menu.addItem(muteItem)

            menu.addItem(NSMenuItem.separator())
        } else {
            let idleItem = NSMenuItem(
                title: "No Channel Playing",
                action: nil,
                keyEquivalent: ""
            )
            idleItem.isEnabled = false
            menu.addItem(idleItem)

            menu.addItem(NSMenuItem.separator())
        }

        // Favorite Channels section
        if !favorites.isEmpty {
            let favoritesHeader = NSMenuItem(
                title: "★ Favorite Channels",
                action: nil,
                keyEquivalent: ""
            )
            favoritesHeader.isEnabled = false
            menu.addItem(favoritesHeader)

            for favorite in favorites.prefix(10) { // Show max 10 favorites
                if let channel = favorite.toChannel() {
                    let isCurrentlyPlaying = player.currentChannel?.id == channel.id
                    let prefix = isCurrentlyPlaying ? "▶︎ " : "   "
                    let favItem = NSMenuItem(
                        title: "\(prefix)\(channel.name)",
                        action: #selector(playFavoriteChannel(_:)),
                        keyEquivalent: ""
                    )
                    favItem.target = self
                    favItem.representedObject = channel
                    menu.addItem(favItem)
                }
            }

            menu.addItem(NSMenuItem.separator())
        }

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Aether",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        item.menu = menu
    }

    @objc private func togglePlayPause() {
        player.togglePlayPause()
    }

    @objc private func stopPlayback() {
        player.stop()
    }

    @objc private func playNext() {
        player.playNext()
    }

    @objc private func playPrevious() {
        player.playPrevious()
    }

    @objc private func toggleMute() {
        player.toggleMute()
    }

    @objc private func playFavoriteChannel(_ sender: NSMenuItem) {
        guard let channel = sender.representedObject as? Channel else { return }
        player.play(channel)
    }
}
