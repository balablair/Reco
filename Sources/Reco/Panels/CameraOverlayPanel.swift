import AppKit
import SwiftUI
import AVFoundation
import os.lock
import RecoKit

// MARK: - Panel

@MainActor
final class CameraOverlayPanel: NSObject, NSWindowDelegate {
    static let shared = CameraOverlayPanel()

    private var panel: NSPanel?
    private var hostContainerView: PiPContainerView?
    private var viewModel: AppViewModel?

    /// 当前录制/Prep 选区（AppKit 屏幕坐标，左下原点），用于约束摄像头拖动范围
    var captureRegion: CGRect = .zero

    private override init() {}

    func show(viewModel: AppViewModel, captureRegion: CGRect) {
        self.viewModel = viewModel
        self.captureRegion = captureRegion
        if let panel {
            positionPanel(panel, in: captureRegion, currentSize: panel.frame.size)
            panel.orderFrontRegardless()
            return
        }
        createPanel(viewModel: viewModel, captureRegion: captureRegion)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        hostContainerView = nil
    }

    /// resize：传入新的 pip 尺寸（支持非正方形）
    func resizePanel(to pipSize: CGSize) {
        guard let panel else { return }
        let clampedW = max(80, min(pipSize.width, 600))
        let clampedH = max(60, min(pipSize.height, 400))
        let panelSize = CGSize(
            width: clampedW + Self.kHandleMargin,
            height: clampedH + Self.kHandleMargin
        )
        let oldFrame = panel.frame
        let dy = panelSize.height - oldFrame.height
        let newOrigin = CGPoint(x: oldFrame.minX, y: oldFrame.minY - dy)
        panel.setFrame(CGRect(origin: newOrigin, size: panelSize), display: true, animate: false)
        hostContainerView?.repositionHandleView()
    }

    /// 当 viewModel.cameraOverlay.size 变化时，根据新尺寸同步 panel 大小
    func syncPanelSize(to pipSize: CGSize) {
        resizePanel(to: pipSize)
    }

    static let kHandleMargin: CGFloat = 12
    static let kDefaultPipSize: CGFloat = 160
    static let kHandleViewSize: CGFloat = 44

    private func createPanel(viewModel: AppViewModel, captureRegion: CGRect) {
        let initSide = Self.kDefaultPipSize
        // 如果当前形状有宽高比，用对应尺寸；否则正方形
        let shape = viewModel.cameraOverlay.style.shape
        let initSize: CGSize
        if let ar = shape.aspectRatio {
            initSize = CGSize(width: initSide * ar, height: initSide)
        } else {
            initSize = CGSize(width: initSide, height: initSide)
        }
        let panelSize = CGSize(
            width: initSize.width + Self.kHandleMargin,
            height: initSize.height + Self.kHandleMargin
        )

        let newOverlay = CameraOverlayLayout(
            origin: viewModel.cameraOverlay.origin,
            size: initSize,
            style: viewModel.cameraOverlay.style
        )
        viewModel.updateCameraOverlay(newOverlay)

        let container = PiPContainerView(viewModel: viewModel)

        let newPanel = NSPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // ⚠️ 关闭 isMovableByWindowBackground！
        // 由 PiPContainerView 自己处理拖窗，tap 事件才能穿透到 SwiftUI
        newPanel.isMovableByWindowBackground = false
        newPanel.hidesOnDeactivate = false
        newPanel.isReleasedWhenClosed = false
        newPanel.contentView = container
        newPanel.delegate = self

        self.hostContainerView = container
        positionPanel(newPanel, in: captureRegion, currentSize: panelSize)
        newPanel.orderFrontRegardless()
        self.panel = newPanel
    }

    private func positionPanel(_ panel: NSPanel, in captureRegion: CGRect, currentSize: CGSize) {
        let margin: CGFloat = 16
        let x = captureRegion.maxX - currentSize.width - margin
        let y = captureRegion.minY + margin
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    // MARK: - Camera Recording Bridge

    /// 开始摄像头独立录制（转发给 CameraCaptureView）
    func startCameraRecording() {
        guard let captureView = findCaptureView() else {
            NSLog("[CameraOverlayPanel] startCameraRecording: captureView not found")
            return
        }
        captureView.startCameraRecording()
    }

    /// 停止摄像头独立录制（转发给 CameraCaptureView）
    func stopCameraRecording(completion: @escaping (URL?) -> Void) {
        guard let captureView = findCaptureView() else {
            completion(nil)
            return
        }
        captureView.stopCameraRecording(completion: completion)
    }

    /// 从 panel 层级中找到 CameraCaptureView
    private func findCaptureView() -> CameraCaptureView? {
        guard let container = hostContainerView else { return nil }
        return findCaptureView(in: container)
    }

    private func findCaptureView(in view: NSView) -> CameraCaptureView? {
        if let cv = view as? CameraCaptureView { return cv }
        for sub in view.subviews {
            if let found = findCaptureView(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - PiPContainerView
//
// panel 的 content view，自己处理所有鼠标事件：
//  - 右下角 kHandleViewSize 区域 → ResizeHandleView 接收，resize
//  - 其余区域 mouseDown+mouseUp 无拖动 → 切换摄像头形状（tap）
//  - 其余区域 mouseDragged 超过阈值 → 移动窗口
//
// ⚠️ 完全不依赖 SwiftUI 手势，避免 NSPanel 事件拦截问题
//
@MainActor
final class PiPContainerView: NSView {

    private var pipViewModel: AppViewModel
    private var resizeHandle: ResizeHandleView?

    // 拖窗状态
    private var dragWindowStart: NSPoint = .zero
    private var dragWindowOrigin: NSPoint = .zero
    private var isDragging = false
    private var mouseDownLocation: NSPoint = .zero

    /// 超过此距离才算拖动（否则算 tap）
    private static let kDragThreshold: CGFloat = 5

    init(viewModel: AppViewModel) {
        self.pipViewModel = viewModel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // SwiftUI hosting — 仅渲染画面，不处理手势
        let rootView = PiPCameraView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        addSubview(hosting)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        // 让 hosting 不参与 hitTest，所有事件由 PiPContainerView 处理
        hosting.isHidden = false

        // ResizeHandleView — 叠在右下角
        let handle = ResizeHandleView(viewModel: viewModel)
        addSubview(handle)
        self.resizeHandle = handle
        repositionHandleView()
    }

    required init?(coder: NSCoder) { fatalError() }

    func repositionHandleView() {
        let sz = CameraOverlayPanel.kHandleViewSize
        resizeHandle?.frame = CGRect(x: bounds.width - sz, y: 0, width: sz, height: sz)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        // 让 hosting 填满（autoresizingMask 会处理，这里只需同步 handle）
        repositionHandleView()
    }

    // 右下角交给 ResizeHandleView；其余区域由 self 处理（不给 hosting）
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let handle = resizeHandle, handle.frame.contains(point) {
            let local = convert(point, to: handle)
            return handle.hitTest(local)
        }
        return bounds.contains(point) ? self : nil
    }

    // MARK: - 事件处理

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        dragWindowStart = NSEvent.mouseLocation
        dragWindowOrigin = window?.frame.origin ?? .zero
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - mouseDownLocation.x
        let dy = current.y - mouseDownLocation.y
        let dist = sqrt(dx * dx + dy * dy)

        if !isDragging && dist > Self.kDragThreshold {
            isDragging = true
        }
        guard isDragging, let win = window else { return }

        let rawX = dragWindowOrigin.x + (current.x - dragWindowStart.x)
        let rawY = dragWindowOrigin.y + (current.y - dragWindowStart.y)
        let panelSize = win.frame.size

        // 约束在 captureRegion 内（如果 captureRegion 有效）
        let region = CameraOverlayPanel.shared.captureRegion
        let clampedOrigin: NSPoint
        if region.width > 0 && region.height > 0 {
            let minX = region.minX
            let maxX = region.maxX - panelSize.width
            let minY = region.minY
            let maxY = region.maxY - panelSize.height
            clampedOrigin = NSPoint(
                x: min(max(rawX, minX), max(maxX, minX)),
                y: min(max(rawY, minY), max(maxY, minY))
            )
        } else {
            clampedOrigin = NSPoint(x: rawX, y: rawY)
        }
        win.setFrameOrigin(clampedOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        defer { isDragging = false }
        guard !isDragging else { return }
        // tap：直接在 native 层切换形状，无需 SwiftUI 手势
        let shape = pipViewModel.cameraOverlay.style.shape
        let next: CameraShape
        switch shape {
        case .circle:      next = .roundedCard
        case .roundedCard: next = .square
        case .square:      next = .rectangle
        case .rectangle:   next = .circle
        }
        pipViewModel.updateCameraShape(next)
        // 形状切换后同步 panel 尺寸（矩形和正方形尺寸不同）
        CameraOverlayPanel.shared.syncPanelSize(to: pipViewModel.cameraOverlay.size)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }
}

// MARK: - ResizeHandleView

@MainActor
final class ResizeHandleView: NSView {

    private var pipViewModel: AppViewModel

    private var isResizing = false
    private var resizeStartMouse: NSPoint = .zero
    private var resizeStartW: CGFloat = CameraOverlayPanel.kDefaultPipSize
    private var resizeStartH: CGFloat = CameraOverlayPanel.kDefaultPipSize

    private var isHovering = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(viewModel: AppViewModel) {
        self.pipViewModel = viewModel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovering else { return }
        NSColor.white.withAlphaComponent(0.75).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        let b = bounds
        for o: CGFloat in [6, 11, 16] {
            path.move(to: NSPoint(x: b.maxX - o - 2, y: b.minY + 2))
            path.line(to: NSPoint(x: b.maxX - 2, y: b.minY + o + 2))
        }
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent)  { isHovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        isResizing = true
        resizeStartMouse = NSEvent.mouseLocation
        let cur = pipViewModel.cameraOverlay.size
        resizeStartW = max(80, cur.width)
        resizeStartH = max(60, cur.height)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizing else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - resizeStartMouse.x
        let dy = resizeStartMouse.y - current.y  // 向下拖 = 放大
        let delta = (dx + dy) / 2.0
        // 保持宽高比缩放
        let shape = pipViewModel.cameraOverlay.style.shape
        let newW: CGFloat
        let newH: CGFloat
        if let ar = shape.aspectRatio {
            // 矩形：以高度为基准
            let newBase = max(60, min(resizeStartH + delta, 400))
            newW = newBase * ar
            newH = newBase
        } else {
            // 正方形/圆形：等比
            let s = max(80, min(resizeStartW + delta, 400))
            newW = s; newH = s
        }
        let newPipSize = CGSize(width: newW, height: newH)
        CameraOverlayPanel.shared.resizePanel(to: newPipSize)
        pipViewModel.cameraOverlay = CameraOverlayLayout(
            origin: pipViewModel.cameraOverlay.origin,
            size: newPipSize,
            style: pipViewModel.cameraOverlay.style
        )
    }

    override func mouseUp(with event: NSEvent) { isResizing = false }
}

// MARK: - SwiftUI 摄像头视图

struct PiPCameraView: View {
    @Bindable var viewModel: AppViewModel
    @State private var isHovering = false

    private var shape: CameraShape { viewModel.cameraOverlay.style.shape }
    private var pipW: CGFloat { viewModel.cameraOverlay.size.width }
    private var pipH: CGFloat { viewModel.cameraOverlay.size.height }

    private var cornerRadius: CGFloat {
        pipCornerRadius(for: shape, in: CGSize(width: pipW, height: pipH))
    }

    var body: some View {
        let margin = CameraOverlayPanel.kHandleMargin
        ZStack(alignment: .bottomTrailing) {
            CameraCaptureSurface(shape: shape, size: min(pipW, pipH), viewModel: viewModel)
                .frame(width: pipW, height: pipH)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 5)
                // 形状切换由 PiPContainerView.mouseUp 原生处理
                .overlay(alignment: .topLeading) {
                    if isHovering {
                        shapeBadge
                            .padding(7)
                            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .topLeading)))
                    }
                }
        }
        .frame(width: pipW + margin, height: pipH + margin)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isHovering)
        .animation(.spring(response: 0.38, dampingFraction: 0.7), value: cornerRadius)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: pipW)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: pipH)
    }

    private var shapeBadge: some View {
        let icon: String = {
            switch shape {
            case .circle:      return "circle.fill"
            case .roundedCard: return "rectangle.fill"
            case .square:      return "square.fill"
            case .rectangle:   return "rectangle.ratio.16.to.9.fill"
            }
        }()
        return Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(5)
            .background(Circle().fill(Color.black.opacity(0.42)))
    }
}

// MARK: - AVCapture NSViewRepresentable

struct CameraCaptureSurface: NSViewRepresentable {
    let shape: CameraShape
    let size: CGFloat
    @Bindable var viewModel: AppViewModel

    func makeNSView(context: Context) -> CameraCaptureView {
        let view = CameraCaptureView()
        view.startCapture()
        return view
    }

    func updateNSView(_ nsView: CameraCaptureView, context: Context) {
        nsView.updateCornerRadius(for: shape, size: size)
        nsView.updateBeauty(viewModel.cameraBeauty)
        nsView.updateMicrophoneEnabled(viewModel.overlayState.microphoneEnabled)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {}
}

// MARK: - CameraCaptureView
//
// 使用 AVCaptureVideoDataOutput + CoreImage 管道：
//  1. 每帧 sampleBuffer 在 videoQueue 处理
//  2. 应用 CoreImage 美颜滤镜（磨皮、亮度、色温、补光）
//  3. 镜像翻转（前置摄像头）
//  4. 渲染到 AVSampleBufferDisplayLayer
//
// 美颜参数盒子：用 os_unfair_lock 保护，完全绕过 Swift actor/isolation 检查
// 因为 AVCaptureVideoDataOutputSampleBufferDelegate 回调在非主线程运行
final class BeautySettingsBox: @unchecked Sendable {
    private var _value = CameraBeautySettings.default
    private var _lock = os_unfair_lock()

    var value: CameraBeautySettings {
        get {
            os_unfair_lock_lock(&_lock)
            defer { os_unfair_lock_unlock(&_lock) }
            return _value
        }
        set {
            os_unfair_lock_lock(&_lock)
            _value = newValue
            os_unfair_lock_unlock(&_lock)
        }
    }
}

// nonisolated：AVCaptureVideoDataOutputSampleBufferDelegate 回调发生在任意线程
// 该类不可被 @MainActor 隔离，否则 Swift 6 运行时会 assert_queue_fail
final class CameraCaptureView: NSView, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    // MARK: Capture
    private var captureSession: AVCaptureSession?
    // 使用 nonisolated(unsafe) 保证跨线程访问安全（setupCapture 在主线程写，captureOutput 在后台线程读）
    // 写操作在 session 启动前完成，不存在并发写，unsafe 是安全的
    private nonisolated(unsafe) var isFrontCamera = true

    // MARK: Display
    private let displayLayer = AVSampleBufferDisplayLayer()

    // MARK: Processing
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let videoQueue = DispatchQueue(label: "camera.beauty.queue", qos: .userInteractive)

    // 美颜参数：用 BeautySettingsBox 避免 Swift 6 actor 隔离检查导致的崩溃
    private let beautyBox = BeautySettingsBox()

    override var wantsUpdateLayer: Bool { true }

    // MARK: Setup

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupDisplayLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDisplayLayer()
    }

    private func setupDisplayLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.frame = bounds
        displayLayer.masksToBounds = true
        layer?.addSublayer(displayLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    // MARK: Corner radius

    func updateCornerRadius(for shape: CameraShape, size: CGFloat) {
        let r: CGFloat
        switch shape {
        case .circle:       r = size / 2
        case .roundedCard:  r = 22
        case .square:       r = 8
        case .rectangle:    r = 14
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.38)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
        )
        displayLayer.cornerRadius = r
        CATransaction.commit()
    }

    // MARK: Beauty update

    func updateBeauty(_ beauty: CameraBeautySettings) {
        beautyBox.value = beauty
    }

    func updateMicrophoneEnabled(_ enabled: Bool) {
        microphoneRecordingEnabled = enabled
        if enabled {
            ensureAudioCaptureConfiguredIfNeeded(requestPermissionIfNeeded: true)
        }
    }

    // MARK: Permission & capture start

    func startCapture() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if granted { self?.setupCapture() } else { self?.showNoCameraPlaceholder() }
                }
            }
        case .authorized:
            // 稍微延迟，确保系统权限状态完全同步后再启动 AVCaptureSession
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupCapture()
            }
        default:
            showNoCameraPlaceholder()
        }
    }

    private func setupCapture() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720

        // 优先前置摄像头
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)

        guard let device else {
            showNoCameraPlaceholder()
            return
        }

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showNoCameraPlaceholder()
            return
        }
        isFrontCamera = (device.position == .front)
        session.addInput(input)

        // VideoDataOutput — 每帧回调做美颜处理
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else {
            showNoCameraPlaceholder()
            return
        }
        session.addOutput(output)

        // 修正视频方向
        if let conn = output.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(0) {
                conn.videoRotationAngle = 0
            }
        }

        self.captureSession = session
        ensureAudioCaptureConfiguredIfNeeded(requestPermissionIfNeeded: false)
        DispatchQueue.global(qos: .userInitiated).async { [weak session] in
            session?.startRunning()
        }
    }

    private func ensureAudioCaptureConfiguredIfNeeded(requestPermissionIfNeeded: Bool) {
        guard microphoneRecordingEnabled,
              !audioCaptureConfigured,
              let session = captureSession else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            configureAudioCapture(on: session)
        case .notDetermined where requestPermissionIfNeeded:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    self?.ensureAudioCaptureConfiguredIfNeeded(requestPermissionIfNeeded: false)
                }
            }
        default:
            break
        }
    }

    private func configureAudioCapture(on session: AVCaptureSession) {
        guard !audioCaptureConfigured,
              let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: audioQueue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input), session.canAddOutput(output) else { return }
        session.addInput(input)
        session.addOutput(output)
        audioCaptureInput = input
        audioCaptureOutput = output
        audioCaptureConfigured = true
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output is AVCaptureAudioDataOutput {
            handleAudioSampleBuffer(sampleBuffer)
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let beauty = beautyBox.value
        let isFront = isFrontCamera

        // --- CoreImage 处理管道 ---
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // 1. 镜像（前置摄像头需要水平翻转）
        // 变换矩阵：先把图像移到 origin=0，水平 scale(-1)，再移回来
        // x' = (ext.maxX - x + ext.origin.x) = ext.maxX + ext.origin.x - x
        // 等价于：translationX = ext.origin.x + ext.width，scaleX = -1
        if isFront {
            let ext = ciImage.extent
            let mirror = CGAffineTransform(translationX: ext.origin.x + ext.width, y: 0)
                .scaledBy(x: -1, y: 1)
            ciImage = ciImage.transformed(by: mirror)
        }

        // 2. 亮度 / 对比度（CIColorControls）
        if beauty.brightness != 0 || beauty.contrast != 1.0 {
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(ciImage, forKey: kCIInputImageKey)
                f.setValue(Float(beauty.brightness), forKey: kCIInputBrightnessKey)
                f.setValue(Float(beauty.contrast), forKey: kCIInputContrastKey)
                f.setValue(1.0, forKey: kCIInputSaturationKey)
                if let out = f.outputImage { ciImage = out }
            }
        }

        // 3. 色温（暖色调）CITemperatureAndTint
        if beauty.warmth != 0 {
            if let f = CIFilter(name: "CITemperatureAndTint") {
                f.setValue(ciImage, forKey: kCIInputImageKey)
                // neutral = [6500, 0]（标准白点），targetNeutral 偏移
                let neutral = CIVector(x: 6500, y: 0)
                let target = CIVector(x: 6500 + beauty.warmth, y: 0)
                f.setValue(neutral, forKey: "inputNeutral")
                f.setValue(target, forKey: "inputTargetNeutral")
                if let out = f.outputImage { ciImage = out }
            }
        }

        // 4. 曝光补偿（补光）CIExposureAdjust
        if beauty.exposure != 0 {
            if let f = CIFilter(name: "CIExposureAdjust") {
                f.setValue(ciImage, forKey: kCIInputImageKey)
                f.setValue(Float(beauty.exposure * 2.0), forKey: kCIInputEVKey)
                if let out = f.outputImage { ciImage = out }
            }
        }

        // 5. 磨皮（高斯模糊 + 亮度混合模拟磨皮）
        if beauty.smoothing > 0 {
            let radius = beauty.smoothing * 6.0   // 最大 6px 模糊
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(ciImage, forKey: kCIInputImageKey)
                blur.setValue(radius, forKey: kCIInputRadiusKey)
                if let blurred = blur.outputImage,
                   let blend = CIFilter(name: "CIBlendWithMask") {
                    // 用暗部蒙版保留边缘细节，只磨平亮部
                    let mask = ciImage.applyingFilter("CIColorMonochrome", parameters: [
                        kCIInputColorKey: CIColor(red: 0.7, green: 0.7, blue: 0.7),
                        kCIInputIntensityKey: 1.0
                    ])
                    blend.setValue(ciImage, forKey: kCIInputBackgroundImageKey)
                    blend.setValue(blurred.cropped(to: ciImage.extent), forKey: kCIInputImageKey)
                    blend.setValue(mask, forKey: kCIInputMaskImageKey)
                    if let out = blend.outputImage { ciImage = out }
                }
            }
        }

        // --- 回写到 CVPixelBuffer ---
        guard let newPixelBuffer = renderToPixelBuffer(ciImage, matching: pixelBuffer) else { return }

        // --- 写入摄像头独立录像（如果正在录制）---
        if let writer = cameraAssetWriter,
           let adaptor = cameraWriterAdaptor,
           let input = cameraWriterInput,
           input.isReadyForMoreMediaData {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if cameraRecordingStartTime == nil {
                cameraRecordingStartTime = pts
                writer.startSession(atSourceTime: pts)
            }
            adaptor.append(newPixelBuffer, withPresentationTime: pts)
        }

        guard let newSampleBuffer = makeSampleBuffer(from: newPixelBuffer, like: sampleBuffer) else { return }

        // CMSampleBuffer 不是 Sendable，用 nonisolated(unsafe) 跨线程传递
        nonisolated(unsafe) let bufferToEnqueue = newSampleBuffer
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.displayLayer.status == .failed {
                self.displayLayer.flush()
            }
            self.displayLayer.enqueue(bufferToEnqueue)
        }
    }

    nonisolated private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = cameraAssetWriter,
              let input = cameraAudioWriterInput,
              input.isReadyForMoreMediaData else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if cameraRecordingStartTime == nil {
            cameraRecordingStartTime = pts
            writer.startSession(atSourceTime: pts)
        }
        input.append(sampleBuffer)
    }

    // MARK: Helpers

    nonisolated private func renderToPixelBuffer(_ image: CIImage, matching original: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(original)
        let h = CVPixelBufferGetHeight(original)
        var newBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: w,
            kCVPixelBufferHeightKey: h,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &newBuffer)
        guard let out = newBuffer else { return nil }
        ciContext.render(image, to: out, bounds: image.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        return out
    }

    nonisolated private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer, like original: CMSampleBuffer) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(original),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(original),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(original)
        )
        var videoInfo: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &videoInfo)
        guard let videoInfo else { return nil }
        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: videoInfo,
            sampleTiming: &timing,
            sampleBufferOut: &newBuffer
        )
        return newBuffer
    }

    // MARK: Placeholder

    private func showNoCameraPlaceholder() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
            let label = NSTextField(labelWithString: "📷")
            label.font = NSFont.systemFont(ofSize: 36)
            label.alignment = .center
            label.backgroundColor = .clear
            self.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: self.centerYAnchor)
            ])
        }
    }

    func stopCapture() {
        captureSession?.stopRunning()
        captureSession = nil
        audioCaptureConfigured = false
        audioCaptureInput = nil
        audioCaptureOutput = nil
    }

    // MARK: - Camera-only recording (AVAssetWriter)

    /// 开始摄像头独立录制，返回输出文件 URL
    @discardableResult
    func startCameraRecording() -> URL {
        stopCameraRecordingInternal()   // 防止重复开始
        ensureAudioCaptureConfiguredIfNeeded(requestPermissionIfNeeded: true)
        let url = makeCameraOutputURL()
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            cameraRecordingOutputURL = nil
            return url
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1280,
                kCVPixelBufferHeightKey as String: 720,
            ]
        )
        guard writer.canAdd(writerInput) else {
            cameraRecordingOutputURL = nil
            return url
        }
        writer.add(writerInput)

        var audioWriterInput: AVAssetWriterInput? = nil
        if microphoneRecordingEnabled {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioWriterInput = input
            }
        }

        writer.startWriting()

        cameraAssetWriter = writer
        cameraWriterInput = writerInput
        cameraAudioWriterInput = audioWriterInput
        cameraWriterAdaptor = adaptor
        cameraRecordingStartTime = nil
        cameraRecordingOutputURL = url
        NSLog("[CameraRecorder] started, output: %@", url.path)
        return url
    }

    /// 停止摄像头独立录制，异步完成后回调（主线程）
    func stopCameraRecording(completion: @escaping (URL?) -> Void) {
        guard let writer = cameraAssetWriter,
              let input  = cameraWriterInput,
              let url    = cameraRecordingOutputURL else {
            completion(nil)
            return
        }
        input.markAsFinished()
        cameraAudioWriterInput?.markAsFinished()
        writer.finishWriting {
            DispatchQueue.main.async {
                NSLog("[CameraRecorder] finished, status=%d", writer.status.rawValue)
                completion(writer.status == .completed ? url : nil)
            }
        }
        cameraAssetWriter = nil
        cameraWriterInput = nil
        cameraAudioWriterInput = nil
        cameraWriterAdaptor = nil
        cameraRecordingOutputURL = nil
    }

    private func stopCameraRecordingInternal() {
        cameraWriterInput?.markAsFinished()
        cameraAudioWriterInput?.markAsFinished()
        cameraAssetWriter?.cancelWriting()
        cameraAssetWriter = nil
        cameraWriterInput = nil
        cameraAudioWriterInput = nil
        cameraWriterAdaptor = nil
        cameraRecordingStartTime = nil
        cameraRecordingOutputURL = nil
    }

    private func makeCameraOutputURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Reco", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("camera-\(UUID().uuidString).mp4")
    }

    // 录制状态（nonisolated(unsafe) 供后台线程访问）
    private nonisolated(unsafe) var cameraAssetWriter: AVAssetWriter? = nil
    private nonisolated(unsafe) var cameraWriterInput: AVAssetWriterInput? = nil
    private nonisolated(unsafe) var cameraAudioWriterInput: AVAssetWriterInput? = nil
    private nonisolated(unsafe) var cameraWriterAdaptor: AVAssetWriterInputPixelBufferAdaptor? = nil
    private nonisolated(unsafe) var cameraRecordingStartTime: CMTime? = nil
    private nonisolated(unsafe) var cameraRecordingOutputURL: URL? = nil
    private nonisolated(unsafe) var microphoneRecordingEnabled = false
    private var audioCaptureConfigured = false
    private var audioCaptureInput: AVCaptureDeviceInput?
    private var audioCaptureOutput: AVCaptureAudioDataOutput?
    private let audioQueue = DispatchQueue(label: "camera.audio.queue", qos: .userInitiated)
}
