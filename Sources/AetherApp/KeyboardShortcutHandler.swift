#if os(macOS)
import AppKit
import AetherCore

/// Monitors local keyboard events and routes them to `PlayerCore`.
/// macOS only — iOS/tvOS use SwiftUI focus-based shortcuts instead.
@MainActor
final class KeyboardShortcutHandler {
    private var monitor: Any?
    private weak var playerCore: PlayerCore?

    /// Called when user presses F to toggle favorite on current channel.
    var onToggleFavorite: (() -> Void)?
    /// Called when user presses / to activate search.
    var onActivateSearch: (() -> Void)?
    /// Called when user presses R to restore last channel.
    var onRestoreLastChannel: (() -> Void)?
    /// Called when user presses Escape to close channel panel.
    var onClosePanel: (() -> Void)?

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
        let cmd = event.modifierFlags.contains(.command)
        let noMod = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        switch event.keyCode {
        // Space → play/pause
        case 49 where noMod:
            player.togglePlayPause(); return nil
        // ← → → prev/next channel
        case 123 where noMod:
            player.playPrevious(); return nil
        case 124 where noMod:
            player.playNext(); return nil
        // ↑ ↓ → also prev/next channel
        case 126 where noMod:
            player.playPrevious(); return nil
        case 125 where noMod:
            player.playNext(); return nil
        // M → mute
        case 46 where noMod:
            player.toggleMute(); return nil
        // F → toggle favorite (no ⌘, that's search)
        case 3 where noMod:
            onToggleFavorite?(); return nil
        // / → activate search
        case 44 where noMod:
            onActivateSearch?(); return nil
        // R / ⌘R → restore last channel
        case 15 where noMod, 15 where cmd:
            onRestoreLastChannel?(); return nil
        // Escape → close panel
        case 53 where noMod:
            onClosePanel?(); return nil
        default:
            return event
        }
    }

    private func isTypingInTextField() -> Bool {
        guard let window = NSApp.keyWindow,
              let responder = window.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
}
#endif
