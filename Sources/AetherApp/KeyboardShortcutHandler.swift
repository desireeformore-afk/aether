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
