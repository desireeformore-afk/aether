import AppKit
import SwiftUI
import AetherCore

/// macOS Menu Bar widget that shows "Now Playing" info and provides quick access to favorite channels.
@MainActor
final class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private let player: PlayerCore
    private var cancellables = Set<AnyCancellable>()

    init(player: PlayerCore) {
        self.player = player
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
    }

    func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        cancellables.removeAll()
    }

    private func observePlayer() {
        player.$currentChannel
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
            .store(in: &cancellables)

        player.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
            .store(in: &cancellables)
    }

    private func updateMenu() {
        guard let item = statusItem else { return }

        let menu = NSMenu()

        // Now Playing section
        if let channel = player.currentChannel {
            let nowPlayingItem = NSMenuItem(
                title: "Now Playing: \(channel.name)",
                action: nil,
                keyEquivalent: ""
            )
            nowPlayingItem.isEnabled = false
            menu.addItem(nowPlayingItem)

            menu.addItem(NSMenuItem.separator())

            // Playback controls
            let playPauseTitle = player.state == .playing ? "Pause" : "Play"
            let playPauseItem = NSMenuItem(
                title: playPauseTitle,
                action: #selector(togglePlayPause),
                keyEquivalent: " "
            )
            playPauseItem.target = self
            menu.addItem(playPauseItem)

            let stopItem = NSMenuItem(
                title: "Stop",
                action: #selector(stopPlayback),
                keyEquivalent: ""
            )
            stopItem.target = self
            menu.addItem(stopItem)

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
}

// MARK: - Combine Import

import Combine
