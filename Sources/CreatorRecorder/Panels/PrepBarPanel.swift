import AppKit
import SwiftUI
import CreatorRecorderKit

// MARK: - 可观察的回调容器（让 PrepBarView 可以在复用 panel 时更新回调）

@Observable
final class PrepBarActions {
    var onRecord: () -> Void = {}
    var onPickArea: () -> Void = {}
    var onQuit: () -> Void = {}
}

@MainActor
final class PrepBarPanel: NSObject, NSWindowDelegate {
    static let shared = PrepBarPanel()

    private var panel: FloatingPanelBase?
    private let actions = PrepBarActions()

    // 记住用户拖动后的位置
    private var savedOrigin: CGPoint?

    private override init() {}

    func show(
        viewModel: AppViewModel,
        onRecord: @escaping () -> Void,
        onPickArea: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        // 每次都更新回调（用 actions 对象传递，view 会自动感知）
        actions.onRecord = onRecord
        actions.onPickArea = onPickArea
        actions.onQuit = onQuit

        // ── 如果 panel 已存在，直接 orderFront 即可，无需重建 ──
        if let existing = panel {
            existing.orderFrontRegardless()
            NSLog("[PrepBar] reusing existing panel, orderFront")
            return
        }

        // ── 首次创建 ──
        let rootView = PrepBarView(
            viewModel: viewModel,
            actions: actions
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true

        let initialSize = CGSize(width: 560, height: 56)
        let origin = savedOrigin ?? defaultOrigin(panelSize: initialSize)
        let frame = CGRect(origin: origin, size: initialSize)

        let newPanel = FloatingPanelBase(contentRect: frame)
        newPanel.contentView = hosting
        newPanel.isMovableByWindowBackground = true
        newPanel.isReleasedWhenClosed = false
        newPanel.delegate = self
        self.panel = newPanel

        newPanel.orderFrontRegardless()
        NSLog("[PrepBar] panel created at origin=\(origin)")

        // 等第一帧渲染后调整尺寸
        fitSizeOnce(panel: newPanel, hosting: hosting, attempt: 0)
    }

    func hide() {
        NSLog("[PrepBar] hide() called")
        if let p = panel {
            savedOrigin = p.frame.origin
            p.orderOut(nil)
            // 保留 panel 对象，下次 show() 直接复用
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        savedOrigin = panel?.frame.origin
    }

    // MARK: - Private

    private func fitSizeOnce(panel: FloatingPanelBase, hosting: NSHostingView<PrepBarView>, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak panel] in
            guard let self, let panel, panel === self.panel else { return }

            let size = hosting.fittingSize
            NSLog("[PrepBar] fittingSize attempt \(attempt): \(size)")

            guard size.width > 30 && size.height > 10 else {
                if attempt < 12 {
                    self.fitSizeOnce(panel: panel, hosting: hosting, attempt: attempt + 1)
                } else {
                    NSLog("[PrepBar] gave up waiting for fittingSize")
                }
                return
            }

            var f = panel.frame
            let centerX = f.midX
            f.size = size
            f.origin.x = centerX - size.width / 2
            if let screen = NSScreen.main {
                let maxY = screen.visibleFrame.maxY - size.height
                f.origin.y = min(f.origin.y, maxY)
            }
            panel.setFrame(f, display: true, animate: false)
            NSLog("[PrepBar] frame adjusted to \(f)")
        }
    }

    private func defaultOrigin(panelSize: CGSize) -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 400, y: 600)
        }
        let f = screen.visibleFrame
        let x = f.midX - panelSize.width / 2
        let y = f.maxY - panelSize.height - 40
        return CGPoint(x: x, y: y)
    }
}
