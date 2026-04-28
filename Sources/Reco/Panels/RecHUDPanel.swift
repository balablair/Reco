import AppKit
import SwiftUI
import RecoKit

@MainActor
final class RecHUDPanel: NSObject {
    static let shared = RecHUDPanel()

    private var window: FloatingPanelBase?
    private let preferredSize = CGSize(width: 280, height: 52)

    private override init() {}

    func show(viewModel: AppViewModel, captureFrame: CGRect, onStop: @escaping () -> Void) {
        let rootView = RecHUDView(viewModel: viewModel, onStop: onStop)

        if let window, let hosting = window.contentView as? NSHostingView<RecHUDView> {
            hosting.rootView = rootView
            window.orderFrontRegardless()
            DispatchQueue.main.async { [weak window, weak hosting] in
                guard let window, let hosting else { return }
                let size = hosting.fittingSize
                if size.width > 0 {
                    var f = window.frame
                    let delta = size.width - f.width
                    f.origin.x -= delta / 2
                    f.size = size
                    window.setFrame(f, display: true)
                }
            }
            return
        }

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]

        let origin = hudOrigin(above: captureFrame)
        let frame = CGRect(origin: origin, size: preferredSize)
        let panel = FloatingPanelBase(contentRect: frame)
        // HUD 需要响应点击，提升到 statusBar 级别确保在录制框之上
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = hosting
        panel.orderFrontRegardless()

        DispatchQueue.main.async { [weak panel] in
            guard let panel else { return }
            let size = hosting.fittingSize
            if size.width > 0 {
                var f = panel.frame
                let delta = size.width - f.width
                f.origin.x -= delta / 2
                f.size = size
                panel.setFrame(f, display: true)
            }
        }
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// 将 HUD 放在录制区域顶部居中
    /// - 优先放在录制区域外（上方 12pt）
    /// - 若超出屏幕（全屏录制等情况），则改为放在录制区域内顶部（内缩 12pt）
    private func hudOrigin(above captureFrame: CGRect) -> CGPoint {
        let x = captureFrame.midX - preferredSize.width / 2
        let screenMaxY = NSScreen.main?.frame.maxY ?? captureFrame.maxY

        let yOutside = captureFrame.maxY + 12
        if yOutside + preferredSize.height <= screenMaxY {
            // 放在录制区域上方
            return CGPoint(x: x, y: yOutside)
        } else {
            // 超出屏幕：退回到录制区域内顶部（内缩 12pt）
            let yInside = captureFrame.maxY - preferredSize.height - 12
            return CGPoint(x: x, y: yInside)
        }
    }
}
