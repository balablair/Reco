import AppKit
import SwiftUI

/// 所有 Overlay Panel 的共享基类 NSPanel
@MainActor
class FloatingPanelBase: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
    }

    func show(at origin: CGPoint) {
        setFrameOrigin(origin)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
