import AppKit
import SwiftUI
import CreatorRecorderKit

@MainActor
final class CompletionPanel: NSObject {
    static let shared = CompletionPanel()

    private var _window: FloatingPanelBase?
    /// 供 AppRuntime 的 shareRecording() 使用
    var window: FloatingPanelBase? { _window }
    private let preferredSize = CGSize(width: 310, height: 260)

    private override init() {}

    func show(
        viewModel: AppViewModel,
        onRedo: @escaping () -> Void,
        onTrim: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onOpenInStudio: @escaping () -> Void
    ) {
        if let _window, let hosting = _window.contentView as? NSHostingView<CompletionCardView> {
            hosting.rootView = CompletionCardView(
                viewModel: viewModel,
                onRedo: onRedo,
                onTrim: onTrim,
                onShare: onShare,
                onOpenInStudio: onOpenInStudio
            )
            _window.orderFrontRegardless()
            return
        }

        let rootView = CompletionCardView(
            viewModel: viewModel,
            onRedo: onRedo,
            onTrim: onTrim,
            onShare: onShare,
            onOpenInStudio: onOpenInStudio
        )
        let origin = defaultOrigin()
        let frame = CGRect(origin: origin, size: preferredSize)
        let panel = FloatingPanelBase(contentRect: frame)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFrontRegardless()
        self._window = panel
    }

    func hide() {
        _window?.orderOut(nil)
    }

    private func defaultOrigin() -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 100, y: 100)
        }
        let frame = screen.visibleFrame
        let x = frame.maxX - preferredSize.width - 24
        let y = frame.minY + 24
        return CGPoint(x: x, y: y)
    }
}
