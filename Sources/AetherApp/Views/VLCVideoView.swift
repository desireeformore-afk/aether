#if os(macOS)
import Foundation
import SwiftUI
import AppKit
import AetherCore

private final class VLCVideoHostView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
}

/// SwiftUI wrapper that provides a stable layer-backed NSView for VLC video rendering.
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
        let view = VLCVideoHostView()
        context.coordinator.attachIfNeeded(view)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attachIfNeeded(nsView)
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach(nsView)
    }

    @MainActor
    public final class Coordinator {
        let ownerID = UUID()
        let player: PlayerCore
        weak var attachedView: NSView?

        init(player: PlayerCore) {
            self.player = player
        }

        func attachIfNeeded(_ view: NSView) {
            guard attachedView !== view else { return }
            player.attachDrawable(view, ownerID: ownerID)
            attachedView = view
        }

        func detach(_ view: NSView) {
            player.detachDrawable(view, ownerID: ownerID)
            if attachedView === view {
                attachedView = nil
            }
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
        context.coordinator.attachIfNeeded(view)
        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attachIfNeeded(uiView)
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach(uiView)
    }

    @MainActor
    public final class Coordinator {
        let ownerID = UUID()
        let player: PlayerCore
        weak var attachedView: UIView?

        init(player: PlayerCore) {
            self.player = player
        }

        func attachIfNeeded(_ view: UIView) {
            guard attachedView !== view else { return }
            player.attachDrawable(view, ownerID: ownerID)
            attachedView = view
        }

        func detach(_ view: UIView) {
            player.detachDrawable(view, ownerID: ownerID)
            if attachedView === view {
                attachedView = nil
            }
        }
    }
}
#endif
