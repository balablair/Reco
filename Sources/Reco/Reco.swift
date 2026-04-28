import AppKit
import AVFoundation
import Observation
import SwiftUI
import ScreenCaptureKit
import RecoKit

enum RecoStatusItemIntent: Equatable {
    case reopenPrimaryInterface
    case terminateApp
}

enum RecoStatusItemAction: Equatable {
    case primaryButtonTap
    case quitMenuItem

    var resolvedIntent: RecoStatusItemIntent {
        switch self {
        case .primaryButtonTap:
            return .reopenPrimaryInterface
        case .quitMenuItem:
            return .terminateApp
        }
    }
}

func statusItemPrimaryClickIntent() -> RecoStatusItemIntent {
    RecoStatusItemAction.primaryButtonTap.resolvedIntent
}

@MainActor
final class RecoStatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let performIntent: (RecoStatusItemIntent) -> Void
    private let statusMenu = NSMenu()

    init(performIntent: @escaping (RecoStatusItemIntent) -> Void) {
        self.performIntent = performIntent
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        statusItem.isVisible = true
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Reco")
                ?? NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Reco")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "Reco"
            button.target = self
            button.action = #selector(handlePrimaryButtonTap)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            NSLog("[StatusItem] configured menu bar icon")
        } else {
            NSLog("[StatusItem] failed to access status item button")
        }

        let openItem = NSMenuItem(title: "打开 Reco", action: #selector(handlePrimaryButtonTap), keyEquivalent: "")
        openItem.target = self
        statusMenu.addItem(openItem)
        statusMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 Reco", action: #selector(handleQuitMenuItem), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    @objc private func handlePrimaryButtonTap() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.popUpMenu(statusMenu)
            return
        }
        performIntent(statusItemPrimaryClickIntent())
    }

    @objc private func handleQuitMenuItem() {
        performIntent(RecoStatusItemAction.quitMenuItem.resolvedIntent)
    }
}

// MARK: - 纯 AppKit 选区覆盖层（彻底解决 SwiftUI DragGesture 失效问题）

/// 直接处理鼠标事件的 NSView，绘制半透明遮罩和选区矩形
/// 支持两种交互模式：
///   1. 拖拽选区（原有逻辑）
///   2. Hover 窗口高亮 + 点击选中（类似 macOS 截图工具）
@MainActor
private final class RegionPickerView: NSView {
    var onCommit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    // 可供 hover 高亮的窗口列表（AppKit 坐标，原点左下）
    // 传入时需已转换到本 NSScreen 的坐标空间
    var windowRects: [CGRect] = []

    private var startPoint: CGPoint?
    private var currentRect: CGRect?       // 拖拽中的草稿选区（view 坐标）
    private var hoveredWindowRect: CGRect? // 当前 hover 高亮的窗口（view 坐标）
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }  // 使用从上到下的坐标系（和 SwiftUI 一致）

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        // 添加 tracking area，确保 mouseMoved 在整个 view 区域都能触发
        // （依赖 window.acceptsMouseMovedEvents 不够可靠，tracking area 更稳定）
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        updateCursor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        startPoint = pt
        isDragging = false
        currentRect = nil
        needsDisplay = true
        updateCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        guard startPoint == nil else { return }  // 拖拽中不更新 hover
        let pt = convert(event.locationInWindow, from: nil)
        // 找所有包含鼠标点的窗口，取面积最小的（通常是最顶层/最精确的窗口）
        // windowRects 按 z-order 从顶到底排列，面积小的通常在视觉最前面
        let candidates = windowRects.filter { $0.contains(pt) }
        hoveredWindowRect = candidates.min(by: { $0.width * $0.height < $1.width * $1.height })
        needsDisplay = true
        updateCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let pt = convert(event.locationInWindow, from: nil)
        isDragging = true
        hoveredWindowRect = nil  // 拖拽时取消 hover
        currentRect = normalizedRect(from: start, to: pt)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else { return }
        let pt = convert(event.locationInWindow, from: nil)

        if !isDragging {
            // 点击（非拖拽）：若 hover 了某个窗口则直接选中它
            if let winRect = hoveredWindowRect {
                startPoint = nil
                currentRect = nil
                isDragging = false
                needsDisplay = true
                NSCursor.arrow.set()
                NSLog("[RegionPicker] click-select window rect=\(winRect)")
                onCommit?(winRect)
                return
            }
            // 点击在空白处：取消
            startPoint = nil
            currentRect = nil
            isDragging = false
            needsDisplay = true
            updateCursor()
            return
        }

        let rect = normalizedRect(from: start, to: pt)
        startPoint = nil
        currentRect = nil
        isDragging = false
        needsDisplay = true
        NSCursor.arrow.set()

        // 最小有效选区 80×60
        guard rect.width > 80, rect.height > 60 else {
            NSLog("[RegionPicker] selection too small (%.0f×%.0f), cancelled", rect.width, rect.height)
            onCancel?()
            return
        }
        NSLog("[RegionPicker] mouseUp: commit rect=\(rect)")
        onCommit?(rect)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // Esc
        if event.keyCode == 53 {
            NSLog("[RegionPicker] Esc pressed, cancelling")
            startPoint = nil
            currentRect = nil
            isDragging = false
            hoveredWindowRect = nil
            NSCursor.arrow.set()
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 选区或 hover 矩形
        let activeRect: CGRect? = currentRect ?? (startPoint == nil ? hoveredWindowRect : nil)

        if let sel = activeRect {
            // 有选区时：只填充选区外的区域（even-odd 凿空），保证遮罩颜色统一
            ctx.saveGState()
            let maskPath = CGMutablePath()
            maskPath.addRect(bounds)
            maskPath.addRoundedRect(in: sel, cornerWidth: 6, cornerHeight: 6)
            ctx.addPath(maskPath)
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()

            // 边框：hover = 蓝色，拖拽 = 白色
            let isHover = (currentRect == nil)
            let strokeColor: CGColor = isHover
                ? CGColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
                : CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(isHover ? 2.5 : 1.5)
            let inset = sel.insetBy(dx: isHover ? 1.25 : 0.75, dy: isHover ? 1.25 : 0.75)
            let borderPath = CGPath(roundedRect: inset, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.addPath(borderPath)
            ctx.strokePath()

            // 标签
            drawLabel(ctx: ctx, rect: sel, isHover: isHover)
        } else {
            // 无选区：整体半透明遮罩
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
            ctx.fill(bounds)
        }

        // 提示文字（无选区 & 无 hover 时显示）
        if currentRect == nil && hoveredWindowRect == nil && startPoint == nil {
            let hint = "点击选择窗口  或  拖拽自定义区域  •  Esc 取消"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85)
            ]
            let str = NSAttributedString(string: hint, attributes: attrs)
            let sz = str.size()
            str.draw(at: CGPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
        }
    }

    // MARK: - Drawing helpers

    /// 绘制选区标签（hover 时蓝色胶囊 + 尺寸，拖拽时白色尺寸文字）
    private func drawLabel(ctx: CGContext, rect: CGRect, isHover: Bool) {
        if isHover {
            let label = String(format: "%.0f × %.0f  点击选中", rect.width, rect.height)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let strSize = str.size()
            let padding: CGFloat = 10
            let tagW = strSize.width + padding * 2
            let tagH: CGFloat = 24
            let tagX = min(max(rect.midX - tagW / 2, 4), bounds.width - tagW - 4)
            let tagY: CGFloat = rect.minY > tagH + 6 ? rect.minY - tagH - 6 : rect.maxY + 6
            let tagRect = CGRect(x: tagX, y: tagY, width: tagW, height: tagH)
            let tagPath = CGPath(roundedRect: tagRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.setFillColor(CGColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.88))
            ctx.addPath(tagPath)
            ctx.fillPath()
            str.draw(at: CGPoint(x: tagX + padding, y: tagY + (tagH - strSize.height) / 2))
        } else {
            let label = String(format: "%.0f × %.0f", rect.width, rect.height)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let strSize = str.size()
            let labelX = min(max(rect.midX - strSize.width / 2, 4), bounds.width - strSize.width - 4)
            let labelY: CGFloat = rect.minY > 24 ? rect.minY - 20 : rect.maxY + 4
            str.draw(at: CGPoint(x: labelX, y: labelY))
        }
    }

    // MARK: - Helpers

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func updateCursor() {
        if hoveredWindowRect != nil && startPoint == nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }
}

@MainActor
final class CursorClickMonitor {
    private var globalMonitor: Any?
    private var configuration: CaptureSessionConfiguration?
    private var startedAt: CFAbsoluteTime = 0
    private var onClick: ((SmartAutoZoomClickEvent) -> Void)?

    func start(configuration: CaptureSessionConfiguration, onClick: @escaping (SmartAutoZoomClickEvent) -> Void) {
        stop()
        self.configuration = configuration
        self.onClick = onClick
        self.startedAt = CFAbsoluteTimeGetCurrent()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, let configuration = self.configuration else { return }
            let timestampSeconds = max(CFAbsoluteTimeGetCurrent() - self.startedAt, 0)
            if let click = makeRecordedCursorClick(
                timestampSeconds: timestampSeconds,
                screenLocation: event.locationInWindow,
                configuration: configuration
            ) {
                Task { @MainActor in
                    self.onClick?(click)
                }
            }
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        configuration = nil
        onClick = nil
        startedAt = 0
    }
}

@MainActor
final class DesktopRegionPicker: NSObject {
    static let shared = DesktopRegionPicker()

    private var overlayWindow: NSWindow?
    private var didCommit = false

    private override init() {}

    func begin(
        on display: DisplaySource,
        windows: [WindowSource] = [],
        onSelection: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        closeOverlay()
        didCommit = false

        // 找到对应 NSScreen（AppKit 坐标，原点左下）
        let screen = NSScreen.screens.first(where: {
            abs($0.frame.width  - display.frame.width)  < 2 &&
            abs($0.frame.height - display.frame.height) < 2
        }) ?? NSScreen.main
        let screenFrame = screen?.frame ?? CGRect(origin: .zero, size: display.frame.size)

        let pickerView = RegionPickerView(frame: CGRect(origin: .zero, size: screenFrame.size))

        // 将窗口 frame（AppKit 坐标，左下原点）转换为 view 坐标（isFlipped=true，左上原点）
        // AppKit 坐标：y 从屏幕底部算起；view 坐标：y 从 view 顶部算起
        // 转换公式：viewY = screenH - appKitY - windowH
        let screenH = screenFrame.height
        pickerView.windowRects = windows.compactMap { win in
            // win.frame 使用全局屏幕坐标（多屏时带偏移）
            // 减去 screenFrame.origin 变成相对当前屏幕的局部坐标
            let localX = win.frame.minX - screenFrame.minX
            let localAppKitY = win.frame.minY - screenFrame.minY
            let viewY = screenH - localAppKitY - win.frame.height
            let viewRect = CGRect(x: localX, y: viewY, width: win.frame.width, height: win.frame.height)
            // 过滤掉超出屏幕范围或太小的窗口
            guard viewRect.width > 80, viewRect.height > 60 else { return nil }
            return viewRect.intersection(CGRect(origin: .zero, size: screenFrame.size))
        }

        pickerView.onCommit = { [weak self] rect in
            guard let self, !self.didCommit else { return }
            self.didCommit = true
            NSLog("[RegionPicker] commit rect=\(rect)")
            self.closeOverlay()
            onSelection(rect)
        }
        pickerView.onCancel = { [weak self] in
            guard let self, !self.didCommit else { return }
            self.didCommit = true
            NSLog("[RegionPicker] cancel")
            self.closeOverlay()
            onCancel()
        }

        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = pickerView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isMovable = false
        window.isReleasedWhenClosed = false

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(pickerView)
        overlayWindow = window
        NSLog("[RegionPicker] overlay window shown: \(screenFrame)")
    }

    private func closeOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow?.close()
        overlayWindow = nil
    }
}

@MainActor
final class StudioWindowController: NSWindowController, NSWindowDelegate {
    init(viewModel: AppViewModel) {
        let hostingView = NSHostingView(rootView: AppShellView(viewModel: viewModel))
        let window = NSWindow(
            contentRect: NSRect(x: 220, y: 180, width: 1440, height: 960),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Reco Studio"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true && window?.isMiniaturized != true
    }

    func showStudio() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideStudio() {
        guard let window, window.isVisible else { return }
        window.orderOut(nil)
    }
}

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let viewModel = AppViewModel()
    private let cursorClickMonitor = CursorClickMonitor()

    private lazy var studioWindowController = StudioWindowController(viewModel: viewModel)

    private init() {}

    func reopenPrimaryInterface() {
        NSApp.activate(ignoringOtherApps: true)
        switch viewModel.phase {
        case .editing:
            studioWindowController.showStudio()
        case .completion:
            showCompletion()
        case .preparation, .recording:
            showPrepBar()
            if viewModel.phase == .preparation {
                showPrepRegionOutline()
                refreshCameraPreview()
            }
        }
    }

    func launch() {
        observePhase()
        observeCameraVisibility()
        observeRecordingFailure()

        // 如果启动阶段是 editing（Studio），直接显示 Studio，完全跳过
        // bootstrap / 录屏权限请求，避免系统弹出「允许录屏」对话框
        if viewModel.phase == .editing {
            studioWindowController.showStudio()
            // 仍然请求摄像头权限（不需要 SCShareableContent，不会触发录屏权限弹窗）
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                await Self.requestCameraPermissionIfNeeded()
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.bootstrap()
            self.showPrepBar()

            // PrepBar 已可见后再请求摄像头权限（此时有 NSPanel 作为 key window，TCC 不会 SIGKILL）
            // 延迟 0.5s 确保 PrepBar 完全显示
            try? await Task.sleep(nanoseconds: 500_000_000)
            await Self.requestCameraPermissionIfNeeded()
            // 只在权限已授权时显示摄像头预览（denied 状态下不调用 AVCapture，避免 SIGKILL）
            let finalStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if finalStatus == .authorized {
                self.refreshCameraPreview()
            }
            // denied/restricted 时：refreshCameraPreview 内部也有权限检查，用户可点摄像头按钮跳转系统设置

            // 主动触发录屏权限检查（让 macOS 弹出「允许录屏」弹窗）
            // 必须在有 UI 窗口可见后调用，TCC 才会弹出提示
            try? await Task.sleep(nanoseconds: 300_000_000)
            await Self.requestScreenCapturePermissionIfNeeded()
        }
    }

    /// 在有可见窗口的情况下请求摄像头权限
    /// anchor 窗口在整个 App 生命周期中保留（永不关闭），避免关窗触发 accessory 模式退出
    private static let permissionAnchorWindow: NSWindow = {
        let w = NSWindow(
            contentRect: NSRect(x: -9999, y: -9999, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return w
    }()

    private static func requestCameraPermissionIfNeeded() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .notDetermined else { return }

        // 显示 anchor 窗口并激活 App，确保 TCC 权限弹窗有 key window 可以依附
        // 注意：anchor 窗口不关闭，避免 accessory 模式下关窗触发 App 退出
        permissionAnchorWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        permissionAnchorWindow.makeKey()

        _ = await AVCaptureDevice.requestAccess(for: .video)

        // 弹窗处理完毕，将 anchor 窗口隐藏（不 close）
        permissionAnchorWindow.orderOut(nil)
    }

    /// 主动触发录屏权限弹窗（首次运行时让 macOS 询问用户是否允许录屏）
    private static func requestScreenCapturePermissionIfNeeded() async {
        // CGPreflightScreenCaptureAccess 直接查 TCC，已授权则无需弹窗
        if CGPreflightScreenCaptureAccess() {
            NSLog("[AppRuntime] Screen capture already granted (CGPreflight)")
            return
        }
        // 先确保有可见的 anchor 窗口（TCC 需要 key window 才能弹出权限弹窗）
        permissionAnchorWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        permissionAnchorWindow.makeKey()
        defer { permissionAnchorWindow.orderOut(nil) }

        // CGRequestScreenCaptureAccess 弹出系统授权对话框（同步返回当前状态）
        let granted = CGRequestScreenCaptureAccess()
        NSLog("[AppRuntime] CGRequestScreenCaptureAccess = %d", granted ? 1 : 0)
    }

    /// 点击 Record 前调用：确保录屏权限已授权
    /// 使用 CGPreflightScreenCaptureAccess() 直接查 TCC，不走 SCShareableContent
    /// 避免 ad-hoc 签名导致 SCShareableContent 误报的问题
    @MainActor
    private func ensureScreenCapturePermission() async -> Bool {
        // CGPreflightScreenCaptureAccess 直接读 TCC 数据库，返回值真实可信
        let granted = CGPreflightScreenCaptureAccess()
        NSLog("[AppRuntime] CGPreflightScreenCaptureAccess = %d", granted ? 1 : 0)

        if granted { return true }

        // 尝试主动请求（首次弹窗）
        let requested = CGRequestScreenCaptureAccess()
        NSLog("[AppRuntime] CGRequestScreenCaptureAccess = %d", requested ? 1 : 0)
        if requested { return true }

        // 权限确实被拒：弹框提示
        let alert = NSAlert()
        alert.messageText = "需要录屏权限"
        alert.informativeText = """
            Reco 无法访问屏幕内容。

            请按以下步骤操作：
            1. 点击「前往系统设置」
            2. 找到 Reco，确保开关已打开
            3. 如果开关已开但仍报错，请先关掉再重新打开
            4. 完成后回来重新点 Record
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "前往系统设置")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        return false
    }

    // MARK: - Phase observation

    private func observePhase() {
        withObservationTracking {
            _ = viewModel.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handlePhaseChange()
                self?.observePhase()
            }
        }
    }

    private func observeRecordingFailure() {
        withObservationTracking {
            _ = viewModel.recordingFailureMessage
        } onChange: { [weak self] in
            Task { @MainActor in
                if let msg = self?.viewModel.recordingFailureMessage {
                    self?.showRecordingErrorAlert(msg)
                }
                self?.observeRecordingFailure()
            }
        }
    }

    private func showRecordingErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "无法开始录制"
        alert.informativeText = message + "\n\n请前往「系统设置 → 隐私与安全性 → 录屏与系统录音」，确认 Reco 已开启权限，然后重启 App 再试。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "前往系统设置")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// 监听 cameraVisible 变化，preparation 阶段实时显示/隐藏摄像头预览
    private func observeCameraVisibility() {
        withObservationTracking {
            _ = viewModel.overlayState.cameraVisible
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.viewModel.phase == .preparation {
                    self.refreshCameraPreview()
                }
                self.observeCameraVisibility()
            }
        }
    }

    /// preparation 阶段根据 cameraVisible 显示/隐藏摄像头
    private func refreshCameraPreview() {
        guard viewModel.phase == .preparation else { return }
        if viewModel.overlayState.cameraVisible {
            // 权限检查：只有已授权才显示摄像头面板
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            guard status == .authorized else {
                NSLog("[Camera] permission not authorized (status=%d), skipping camera panel", status.rawValue)
                CameraOverlayPanel.shared.hide()
                return
            }
            let captureFrame = captureScreenFrame()
            CameraOverlayPanel.shared.show(viewModel: viewModel, captureRegion: captureFrame)
        } else {
            CameraOverlayPanel.shared.hide()
        }
    }

    private func handlePhaseChange() {
        NSLog("[AppRuntime] handlePhaseChange: phase=%@", String(describing: viewModel.phase))
        switch viewModel.phase {
        case .preparation:
            cursorClickMonitor.stop()
            RecHUDPanel.shared.hide()
            RecordingOutlinePanel.shared.hide()
            CompletionPanel.shared.hide()
            TeleprompterPanel.shared.hide()
            studioWindowController.hideStudio()
            showPrepBar()
            // preparation 阶段：显示选区虚线框
            showPrepRegionOutline()
            // preparation 阶段：如果摄像头已开启则显示预览
            refreshCameraPreview()
            // 如果从 editing 切过来，可能还没做过 bootstrap（跳过了录屏权限请求）
            // 在用户主动进入 prep 时，才懒加载屏幕数据 & 请求录屏权限
            if viewModel.availableDisplays == [.placeholder] || viewModel.availableDisplays.isEmpty {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.viewModel.bootstrap()
                    self.showPrepRegionOutline()
                    // 延迟一点再请求录屏权限，确保 PrepBar 窗口已经可见
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await Self.requestScreenCapturePermissionIfNeeded()
                }
            }

        case .recording:
            PrepBarPanel.shared.hide()
            CompletionPanel.shared.hide()
            PrepRegionOutlinePanel.shared.hide()
            PrepDimmingPanel.shared.hide()
            let captureConfiguration = viewModel.makeCaptureSessionConfiguration()
            cursorClickMonitor.start(configuration: captureConfiguration) { [weak self] click in
                self?.viewModel.appendRecordedCursorClick(click)
            }
            let captureFrame = captureScreenFrame()
            RecordingOutlinePanel.shared.show(frame: captureFrame)
            RecHUDPanel.shared.show(viewModel: viewModel, captureFrame: captureFrame) { [weak self] in
                self?.stopRecording()
            }
            // 摄像头画中画：定位在录制选区右下角，仅在权限已授权时显示
            if viewModel.overlayState.cameraVisible
                && AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                CameraOverlayPanel.shared.show(viewModel: viewModel, captureRegion: captureFrame)
                // 同步启动摄像头独立录制
                CameraOverlayPanel.shared.startCameraRecording()
            }
            // 提词器：有文本时自动显示
            if viewModel.overlayState.teleprompterVisible && !viewModel.teleprompterText.isEmpty {
                TeleprompterPanel.shared.show(viewModel: viewModel)
            }

        case .completion:
            cursorClickMonitor.stop()
            RecHUDPanel.shared.hide()
            RecordingOutlinePanel.shared.hide()
            PrepRegionOutlinePanel.shared.hide()
            PrepDimmingPanel.shared.hide()
            PrepBarPanel.shared.hide()
            CameraOverlayPanel.shared.hide()
            TeleprompterPanel.shared.hide()
            showCompletion()

        case .editing:
            cursorClickMonitor.stop()
            CompletionPanel.shared.hide()
            PrepBarPanel.shared.hide()
            PrepRegionOutlinePanel.shared.hide()
            PrepDimmingPanel.shared.hide()
            CameraOverlayPanel.shared.hide()
            studioWindowController.showStudio()
        }
    }

    // MARK: - Show helpers

    /// 在 prep 阶段展示当前选区的白色虚线框 + 选区外暗色遮罩
    private func showPrepRegionOutline() {
        let frame = captureScreenFrame()
        // 选区太小或无效时不显示
        guard frame.width > 40, frame.height > 40 else {
            PrepRegionOutlinePanel.shared.hide()
            PrepDimmingPanel.shared.hide()
            return
        }
        PrepRegionOutlinePanel.shared.hide()
        // 选区外暗色遮罩：在同一层里同时绘制遮罩与边框，避免多窗口叠加产生边缘误差
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
        PrepDimmingPanel.shared.show(selectionFrame: frame, screenFrame: screenFrame)
    }

    private func showPrepBar() {
        NSLog("[PrepBar] showPrepBar() called, phase=%@", String(describing: viewModel.phase))
        PrepBarPanel.shared.show(
            viewModel: viewModel,
            onRecord: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    let ok = await self.ensureScreenCapturePermission()
                    if ok {
                        self.viewModel.startRecordingSession()
                    }
                }
            },
            onPickArea: { [weak self] in
                self?.startRegionPicker()
            },
            onQuit: { [weak self] in
                self?.terminate()
            }
        )
    }

    private func showCompletion() {
        CompletionPanel.shared.show(
            viewModel: viewModel,
            onRedo: { [weak self] in
                self?.viewModel.redo()
            },
            onExportSource: { [weak self] in
                self?.exportSourceAssetsFromCompletion()
            },
            onOpenInStudio: { [weak self] in
                self?.viewModel.openInStudio()
            }
        )
    }

    // MARK: - Actions

    private func stopRecording() {
        Task { @MainActor in
            // 先停止摄像头独立录制，等文件 finalize 后再停屏幕
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                CameraOverlayPanel.shared.stopCameraRecording { [weak self] cameraURL in
                    self?.viewModel.pendingCameraFileURL = cameraURL
                    if let url = cameraURL {
                        NSLog("[AppRuntime] camera recording saved: %@", url.path)
                    }
                    continuation.resume()
                }
            }
            await viewModel.stopRecordingSession()
        }
    }

    private func startRegionPicker() {
        NSLog("[AppRuntime] startRegionPicker: hiding PrepBar and starting picker")
        PrepBarPanel.shared.hide()
        // 隐藏 Prep 阶段的虚线框和遮罩，避免与选区工具的全屏遮罩视觉叠加不一致
        PrepRegionOutlinePanel.shared.hide()
        PrepDimmingPanel.shared.hide()
        viewModel.setRegionSelection(active: true)
        DesktopRegionPicker.shared.begin(
            on: viewModel.selectedDisplaySource,
            windows: viewModel.availableWindows,
            onSelection: { [weak self] rect in
                NSLog("[AppRuntime] onSelection callback: rect=\(rect)")
                guard let self else {
                    NSLog("[AppRuntime] onSelection: self is nil!")
                    return
                }
                self.viewModel.applyScreenSelection(rect)
                self.viewModel.setRegionSelection(active: false)
                NSLog("[AppRuntime] onSelection: calling showPrepBar")
                self.showPrepBar()
                // 选区更新后显示虚线框
                self.showPrepRegionOutline()
                // 选区更新后刷新摄像头位置
                self.refreshCameraPreview()
            },
            onCancel: { [weak self] in
                NSLog("[AppRuntime] onCancel callback")
                guard let self else { return }
                self.viewModel.setRegionSelection(active: false)
                self.showPrepBar()
            }
        )
    }

    private func exportSourceAssetsFromCompletion() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.viewModel.exportSourceAssets()
            guard case let .completed(results) = self.viewModel.sourceExportState else { return }
            let urls = results.map(\.fileURL)
            guard !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    // MARK: - Capture frame

    private func captureScreenFrame() -> CGRect {
        // 窗口模式：直接用 windowSource 的 AppKit frame（左下原点）
        if let win = viewModel.selectedWindowSource {
            return win.frame
        }
        guard let screen = NSScreen.main else {
            return CGRect(x: 100, y: 100, width: 1280, height: 720)
        }
        let region = viewModel.captureRegion
        let screenHeight = screen.frame.height
        // captureRegion 使用 AppKit 坐标系（原点在左下）
        return CGRect(
            x: region.origin.x,
            y: screenHeight - region.origin.y - region.size.height,
            width: region.size.width,
            height: region.size.height
        )
    }

    func terminate() {
        Task {
            if viewModel.isRecordingActive {
                await viewModel.stopRecordingSession()
            }
            NSApp.terminate(nil)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = AppRuntime.shared
    private var statusItemController: RecoStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        statusItemController = RecoStatusItemController { [weak self] intent in
            self?.handleStatusItemIntent(intent)
        }
        runtime.launch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        _ = sender
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = sender
        if !flag {
            runtime.reopenPrimaryInterface()
        }
        return true
    }

    private func handleStatusItemIntent(_ intent: RecoStatusItemIntent) {
        switch intent {
        case .reopenPrimaryInterface:
            runtime.reopenPrimaryInterface()
        case .terminateApp:
            runtime.terminate()
        }
    }
}
