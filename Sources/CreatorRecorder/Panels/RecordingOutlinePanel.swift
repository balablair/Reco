import AppKit
import SwiftUI

/// 录制区域红框透明覆盖窗口，不拦截鼠标事件
@MainActor
final class RecordingOutlinePanel: NSObject {
    static let shared = RecordingOutlinePanel()

    private var window: NSPanel?

    private override init() {}

    func show(frame: CGRect) {
        hide()
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        let outline = NSHostingView(rootView: RecordingOutlineView())
        panel.contentView = outline
        panel.orderFrontRegardless()
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}

private struct RecordingOutlineView: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Color(red: 1, green: 0.23, blue: 0.19).opacity(0.9), lineWidth: 1.5)
            .ignoresSafeArea()
    }
}
