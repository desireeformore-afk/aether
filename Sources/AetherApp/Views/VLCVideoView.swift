#if os(macOS)
import SwiftUI
import AppKit
import AetherCore

/// SwiftUI wrapper that provides a Metal-backed NSView for VLC video rendering.
public struct VLCVideoView: NSViewRepresentable {
    public let player: PlayerCore

    public init(player: PlayerCore) {
        self.player = player
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        // Enforce letterbox: video scales to fit while preserving aspect ratio
        view.layer?.contentsGravity = .resizeAspect
        self.player.attachDrawable(view)
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
