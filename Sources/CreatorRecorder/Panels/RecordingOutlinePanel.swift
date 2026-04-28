import AppKit
import SwiftUI

// MARK: - 录制中红框

/// 录制区域红框透明覆盖窗口，不拦截鼠标事件
@MainActor
final class RecordingOutlinePanel: NSObject {
    static let shared = RecordingOutlinePanel()

    private var window: NSPanel?

    private override init() {}

    func show(frame: CGRect) {
        hide()
        let panel = makePanel(frame: frame)
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

    private func makePanel(frame: CGRect) -> NSPanel {
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
        return panel
    }
}

private struct RecordingOutlineView: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Color(red: 1, green: 0.23, blue: 0.19).opacity(0.9), lineWidth: 1.5)
            .ignoresSafeArea()
    }
}

// MARK: - Prep 阶段选区虚线框

/// Preparation 阶段显示的白色虚线选区边框，不拦截鼠标事件
@MainActor
final class PrepRegionOutlinePanel: NSObject {
    static let shared = PrepRegionOutlinePanel()

    private var window: NSPanel?

    private override init() {}

    /// frame 是 AppKit 坐标（左下原点）
    func show(frame: CGRect) {
        if let window {
            // 复用，直接更新位置和大小
            window.setFrame(frame, display: true, animate: false)
            window.orderFrontRegardless()
            return
        }

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

        let view = NSHostingView(rootView: PrepRegionOutlineView())
        panel.contentView = view
        panel.orderFrontRegardless()
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}

// MARK: - Prep 阶段选区外暗色遮罩

/// 在 Preparation 阶段用四块半透明遮罩窗口覆盖选区以外的区域，选区本身保持透明
/// 使用四块独立窗口（上/下/左/右）拼接，避免单窗口挖空的复杂性
@MainActor
final class PrepDimmingPanel: NSObject {
    static let shared = PrepDimmingPanel()

    private var panel: NSPanel?

    private override init() {}

    /// selectionFrame: AppKit 坐标（左下原点），screenFrame: 全屏
    func show(selectionFrame: CGRect, screenFrame: CGRect) {
        if let panel {
            panel.setFrame(screenFrame, display: true, animate: false)
            panel.contentView = NSHostingView(
                rootView: PrepDimmingView(selectionFrame: selectionFrame, screenFrame: screenFrame)
            )
            panel.orderFrontRegardless()
            return
        }

        let panel = makePanel(frame: screenFrame)
        panel.contentView = NSHostingView(
            rootView: PrepDimmingView(selectionFrame: selectionFrame, screenFrame: screenFrame)
        )
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func makePanel(frame: CGRect) -> NSPanel {
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
        panel.isReleasedWhenClosed = false
        return panel
    }
}

private struct PrepDimmingView: View {
    let selectionFrame: CGRect
    let screenFrame: CGRect

    var body: some View {
        Canvas { ctx, size in
            let bounds = CGRect(origin: .zero, size: size)
            let selection = makePrepDisplayRect(selectionFrame: selectionFrame, screenFrame: screenFrame)
            let cutoutRect = makePrepSelectionCutoutRect(selectionRect: selection)
            let cutoutPath = Path(makePrepSelectionCutoutPath(selectionRect: selection))
            let maskPath = Path(makePrepSelectionMaskPath(bounds: bounds, selectionRect: selection))

            ctx.fill(maskPath, with: .color(Color.black.opacity(0.52)), style: FillStyle(eoFill: true))
            ctx.stroke(
                cutoutPath,
                with: .color(Color.white.opacity(0.85)),
                style: StrokeStyle(lineWidth: PrepRegionStyle.lineWidth, dash: [8, 6])
            )
            drawPrepCornerMarks(in: &ctx, rect: cutoutRect)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

func makePrepDisplayRect(selectionFrame: CGRect, screenFrame: CGRect) -> CGRect {
    let localX = selectionFrame.minX - screenFrame.minX
    let localAppKitY = selectionFrame.minY - screenFrame.minY
    let viewY = screenFrame.height - localAppKitY - selectionFrame.height
    return CGRect(x: localX, y: viewY, width: selectionFrame.width, height: selectionFrame.height)
}

func makePrepSelectionCutoutRect(selectionRect: CGRect) -> CGRect {
    selectionRect.insetBy(dx: PrepRegionStyle.cutoutInset, dy: PrepRegionStyle.cutoutInset)
}

func makePrepSelectionCutoutPath(selectionRect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let cutoutRect = makePrepSelectionCutoutRect(selectionRect: selectionRect)
    let cutoutCorner = max(0, PrepRegionStyle.cornerRadius - PrepRegionStyle.cutoutInset)
    path.addRoundedRect(
        in: cutoutRect,
        cornerWidth: cutoutCorner,
        cornerHeight: cutoutCorner
    )
    return path
}

func makePrepSelectionMaskPath(bounds: CGRect, selectionRect: CGRect) -> CGPath {
    let path = CGMutablePath()
    path.addRect(bounds)
    path.addPath(makePrepSelectionCutoutPath(selectionRect: selectionRect))
    return path
}

private func drawPrepCornerMarks(in ctx: inout GraphicsContext, rect: CGRect) {
    let len: CGFloat = 14
    let thick: CGFloat = 2.5
    let corners: [(CGPoint, Bool, Bool)] = [
        (CGPoint(x: rect.minX, y: rect.maxY), false, false),
        (CGPoint(x: rect.maxX, y: rect.maxY), true, false),
        (CGPoint(x: rect.minX, y: rect.minY), false, true),
        (CGPoint(x: rect.maxX, y: rect.minY), true, true)
    ]

    for (corner, xFlip, yFlip) in corners {
        var path = Path()
        let dx = xFlip ? -len : len
        let dy = yFlip ? len : -len
        path.move(to: CGPoint(x: corner.x + dx, y: corner.y))
        path.addLine(to: corner)
        path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy))
        ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: thick, lineCap: .round))
    }
}

private enum PrepRegionStyle {
    static let cornerRadius: CGFloat = 6
    static let lineWidth: CGFloat = 1.5
    static let cutoutInset: CGFloat = lineWidth / 2
}

private struct PrepRegionOutlineView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: PrepRegionStyle.cornerRadius, style: .continuous)
            .strokeBorder(
                style: StrokeStyle(lineWidth: PrepRegionStyle.lineWidth, dash: [8, 6])
            )
            .foregroundStyle(Color.white.opacity(0.85))
            .ignoresSafeArea()
    }
}
