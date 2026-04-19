#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Scroll Wheel Modifier

private struct ScrollWheelModifier: ViewModifier {
    let handler: (NSEvent) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelView(handler: handler)
        )
    }
}

private struct ScrollWheelView: NSViewRepresentable {
    let handler: (NSEvent) -> Void

    func makeNSView(context: Context) -> _ScrollReceiver {
        let v = _ScrollReceiver()
        v.handler = handler
        return v
    }

    func updateNSView(_ nsView: _ScrollReceiver, context: Context) {
        nsView.handler = handler
    }
}

final class _ScrollReceiver: NSView {
    var handler: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        handler?(event)
    }
}

// MARK: - Public API

extension View {
    /// Receives macOS scroll-wheel events.
    func onScrollWheel(_ handler: @escaping (NSEvent) -> Void) -> some View {
        modifier(ScrollWheelModifier(handler: handler))
    }
}
#endif
