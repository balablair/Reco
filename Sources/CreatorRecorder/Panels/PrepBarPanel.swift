import AppKit
import SwiftUI
import CreatorRecorderKit

@MainActor
final class PrepBarPanel: NSObject, NSWindowDelegate {
    static let shared = PrepBarPanel()

    private var window: FloatingPanelBase?
    private let preferredSize = CGSize(width: 430, height: 58)

    private override init() {}

    func show(
        viewModel: AppViewModel,
        onRecord: @escaping () -> Void,
        onPickArea: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        if let window {
            if let hosting = window.contentView as? NSHostingView<PrepBarView> {
                hosting.rootView = PrepBarView(
                    viewModel: viewModel,
                    onRecord: onRecord,
                    onPickArea: onPickArea,
                    onQuit: onQuit
                )
            }
            window.orderFrontRegardless()
            return
        }

        let rootView = PrepBarView(
            viewModel: viewModel,
            onRecord: onRecord,
            onPickArea: onPickArea,
            onQuit: onQuit
        )
        let origin = defaultOrigin()
        let frame = CGRect(origin: origin, size: preferredSize)
        let panel = FloatingPanelBase(contentRect: frame)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.orderFrontRegardless()
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func defaultOrigin() -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 400, y: 80)
        }
        let frame = screen.visibleFrame
        let x = frame.midX - preferredSize.width / 2
        let y = frame.minY + 60
        return CGPoint(x: x, y: y)
    }
}
