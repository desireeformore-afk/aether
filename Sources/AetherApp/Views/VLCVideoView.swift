#if os(macOS)
import SwiftUI
import AppKit
import AetherCore

/// SwiftUI wrapper that provides a Metal-backed NSView for VLC video rendering.
///
/// VLC requires a raw NSView to render into — it bypasses SwiftUI's layer system entirely
/// and draws directly into the view's CALayer via Metal/OpenGL.
/// This wrapper creates the view, attaches PlayerCore, and keeps the background black.
public struct VLCVideoView: NSViewRepresentable {
    public let player: PlayerCore

    public init(player: PlayerCore) {
        self.player = player
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        // Tell VLC to render into this NSView.
        // Must happen on the same thread the view was created on (MainActor).
        player.attachDrawable(view)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // Nothing to update — VLC manages its own render cycle
    }
}
#endif

#if os(iOS) || os(tvOS)
import SwiftUI
import UIKit
import AetherCore

/// SwiftUI wrapper for VLC video rendering on iOS/tvOS.
public struct VLCVideoView: UIViewRepresentable {
    public let player: PlayerCore

    public init(player: PlayerCore) {
        self.player = player
    }

    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.attachDrawable(view)
        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
