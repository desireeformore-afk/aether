import AppKit
import AetherCore

/// Monitors local keyboard events and routes them to `PlayerCore`.
///
/// Start/stop monitoring with the main window lifecycle.
/// Uses `addLocalMonitorForEvents` — works for key events in the app's own windows.
@MainActor
final class KeyboardShortcutHandler {
    private var monitor: Any?
    private weak var playerCore: PlayerCore?

    init(playerCore: PlayerCore) {
        self.playerCore = playerCore
    }

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

    // MARK: - Private

    private func handle(event: NSEvent, player: PlayerCore) -> NSEvent? {
        // Don't intercept when user is typing in a text field
        guard !isTypingInTextField() else { return event }

        switch event.keyCode {
        case 49: // Space — play/pause
            player.togglePlayPause()
            return nil

        case 123: // Left arrow — previous channel
            player.playPrevious()
            return nil

        case 124: // Right arrow — next channel
            player.playNext()
            return nil

        case 46 where !event.modifierFlags.contains(.command): // M — mute (no cmd)
            player.toggleMute()
            return nil

        default:
            return event
        }
    }

    /// Returns true if a text field is currently the first responder.
    private func isTypingInTextField() -> Bool {
        guard let window = NSApp.keyWindow,
              let responder = window.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }
}
