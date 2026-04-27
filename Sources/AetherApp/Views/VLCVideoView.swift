#if os(macOS)
import Foundation
import SwiftUI
import AppKit
import AetherCore

/// SwiftUI wrapper that provides a Metal-backed NSView for VLC video rendering.
@MainActor
public struct VLCVideoView: NSViewRepresentable {
    public let player: PlayerCore

    public init(player: PlayerCore) {
        self.player = player
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(player: player)
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        // Enforce letterbox: video scales to fit while preserving aspect ratio
        view.layer?.contentsGravity = .resizeAspect
        player.attachDrawable(view, ownerID: context.coordinator.ownerID)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        player.attachDrawable(nsView, ownerID: context.coordinator.ownerID)
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.player.detachDrawable(nsView, ownerID: coordinator.ownerID)
    }

    public final class Coordinator {
        let ownerID = UUID()
        let player: PlayerCore

        init(player: PlayerCore) {
            self.player = player
        }
    }
}
#endif

#if os(iOS) || os(tvOS)
import Foundation
import SwiftUI
import UIKit
import AetherCore

/// SwiftUI wrapper for VLC video rendering on iOS/tvOS.
@MainActor
public struct VLCVideoView: UIViewRepresentable {
    public let player: PlayerCore

    public init(player: PlayerCore) {
        self.player = player
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(player: player)
    }

    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.attachDrawable(view, ownerID: context.coordinator.ownerID)
        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        player.attachDrawable(uiView, ownerID: context.coordinator.ownerID)
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.player.detachDrawable(uiView, ownerID: coordinator.ownerID)
    }

    public final class Coordinator {
        let ownerID = UUID()
        let player: PlayerCore

        init(player: PlayerCore) {
            self.player = player
        }
    }
}
#endif
