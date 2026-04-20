import AppKit
import SwiftUI
import CreatorRecorderKit

@MainActor
final class RecHUDPanel: NSObject {
    static let shared = RecHUDPanel()

    private var window: FloatingPanelBase?
    private let preferredSize = CGSize(width: 220, height: 48)

    private override init() {}

    func show(viewModel: AppViewModel, captureFrame: CGRect, onStop: @escaping () -> Void) {
        if let window, let hosting = window.contentView as? NSHostingView<RecHUDView> {
            hosting.rootView = RecHUDView(viewModel: viewModel, onStop: onStop)
            window.orderFrontRegardless()
            return
        }

        let rootView = RecHUDView(viewModel: viewModel, onStop: onStop)
        let origin = hudOrigin(above: captureFrame)
        let frame = CGRect(origin: origin, size: preferredSize)
        let panel = FloatingPanelBase(contentRect: frame)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFrontRegardless()
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// 将 HUD 放在录制区域顶部居中
    private func hudOrigin(above captureFrame: CGRect) -> CGPoint {
        let x = captureFrame.midX - preferredSize.width / 2
        let y = captureFrame.maxY + 12
        return CGPoint(x: x, y: y)
    }
}
