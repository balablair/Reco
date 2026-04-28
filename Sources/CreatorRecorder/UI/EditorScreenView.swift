import AppKit
import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers
import CreatorRecorderKit

// MARK: - 主编辑界面

struct EditorScreenView: View {
    @Bindable var viewModel: AppViewModel
    /// 共享的 AVPlayer，画布和控制条用同一个实例
    @State private var sharedPlayer: AVPlayer? = nil
    /// 摄像头独立录像的 AVPlayer
    @State private var cameraPlayer: AVPlayer? = nil

    var body: some View {
        HStack(spacing: 0) {
            // ── 左侧：画布编辑器 ──
            CanvasEditorPanel(viewModel: viewModel, sharedPlayer: sharedPlayer, cameraPlayer: cameraPlayer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.15)

            // ── 右侧：平台选择 + 背景 + 导出 ──
            StudioSidePanel(viewModel: viewModel, sharedPlayer: sharedPlayer, cameraPlayer: cameraPlayer)
                .frame(width: 290)
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { setupPlayers() }
        .onChange(of: viewModel.latestRecording?.fileURL)       { setupPlayers() }
        .onChange(of: viewModel.latestRecording?.cameraFileURL) { setupPlayers() }
    }

    private func setupPlayers() {
        // 屏幕录像 player
        if let url = viewModel.latestRecording?.fileURL,
           FileManager.default.fileExists(atPath: url.path) {
            let same = (sharedPlayer?.currentItem?.asset as? AVURLAsset)?.url == url
            if !same { sharedPlayer = AVPlayer(url: url) }
        }
        // 摄像头 player
        if let url = viewModel.latestRecording?.cameraFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            let same = (cameraPlayer?.currentItem?.asset as? AVURLAsset)?.url == url
            if !same { cameraPlayer = AVPlayer(url: url) }
        } else {
            cameraPlayer = nil
        }

        // 音频跟随摄像头：有摄像头录像时，屏幕录像静音（避免双声道叠加）
        let hasCameraAudio = cameraPlayer != nil
        sharedPlayer?.isMuted = hasCameraAudio
        cameraPlayer?.isMuted = false
    }
}

// MARK: - 画布编辑器（左侧主区域）

private struct CanvasEditorPanel: View {
    @Bindable var viewModel: AppViewModel
    let sharedPlayer: AVPlayer?
    let cameraPlayer: AVPlayer?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.925, green: 0.925, blue: 0.937),
                    Color(red: 0.965, green: 0.969, blue: 0.976)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // 画布本体
            GeometryReader { geo in
                let canvas = canvasRect(in: geo.size)
                let shellInset: CGFloat = 18
                let shellRect = canvas.insetBy(dx: -shellInset, dy: -shellInset)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.white.opacity(0.16))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.56), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.08), radius: 26, y: 10)
                        .frame(width: shellRect.width, height: shellRect.height)
                        .position(x: shellRect.midX, y: shellRect.midY)

                    // 画布容器（有边框阴影）
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black)
                        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
                        .frame(width: canvas.width, height: canvas.height)
                        .position(x: canvas.midX, y: canvas.midY)

                    // 画布内容
                    CanvasContent(
                        viewModel: viewModel,
                        canvasSize: CGSize(width: canvas.width, height: canvas.height),
                        sharedPlayer: sharedPlayer,
                        cameraPlayer: cameraPlayer
                    )
                    .frame(width: canvas.width, height: canvas.height)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .position(x: canvas.midX, y: canvas.midY)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { canvasSize = CGSize(width: canvas.width, height: canvas.height) }
                .onChange(of: geo.size) { canvasSize = CGSize(width: canvas.width, height: canvas.height) }
            }
        }
    }

    /// 计算画布在视图内的实际 Rect（保持平台宽高比，留 40pt padding）
    private func canvasRect(in viewSize: CGSize) -> CGRect {
        let padding: CGFloat = 76
        let available = CGSize(width: viewSize.width - padding * 2, height: viewSize.height - padding * 2)
        let ar = viewModel.currentCanvasLayout.platform.aspectRatio  // W/H
        let fitByWidth  = CGSize(width: available.width,  height: available.width  / ar)
        let fitByHeight = CGSize(width: available.height * ar, height: available.height)
        let size = fitByWidth.height <= available.height ? fitByWidth : fitByHeight
        let origin = CGPoint(
            x: (viewSize.width  - size.width)  / 2,
            y: (viewSize.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }
}

// MARK: - 画布内容（背景 + 视频层 + PiP 层）

private struct CanvasContent: View {
    @Bindable var viewModel: AppViewModel
    let canvasSize: CGSize
    let sharedPlayer: AVPlayer?
    let cameraPlayer: AVPlayer?

    @State private var selectedElement: CanvasElement? = nil
    @State private var screenCropMode = false

    enum CanvasElement { case screen, pip }

    var body: some View {
        ZStack {
            // 1. 背景层
            CanvasBackgroundView(background: viewModel.currentCanvasLayout.background)

            // 点击空白区域取消选中
            Color.clear.contentShape(Rectangle())
                .onTapGesture {
                    selectedElement = nil
                    screenCropMode = false
                }

            // 2. 屏幕录像层（支持裁剪手柄）
            CanvasCropableElement(
                frame: viewModel.currentCanvasLayout.screenFrame,
                crop: viewModel.currentCanvasLayout.screenCrop,
                canvasSize: canvasSize,
                isSelected: selectedElement == .screen,
                isCropMode: screenCropMode,
                onSelect: { selectedElement = .screen },
                onCropModeChange: { screenCropMode = $0 },
                onFrameChange: { viewModel.updateCanvasScreenFrame($0) },
                onCropChange: { viewModel.updateCanvasScreenCrop($0) }
            ) {
                // 裁剪模式下显示完整视频（不放大不偏移），让 cropOverlay 的遮罩决定可见区域
                // 普通模式下用实际 crop 值显示已裁剪的内容
                ScreenVideoLayer(
                    viewModel: viewModel,
                    player: sharedPlayer,
                    baseCrop: screenCropMode ? .full : viewModel.currentCanvasLayout.screenCrop
                )
            }

            // 3. PiP 摄像头层
            if let pipFrame = viewModel.currentCanvasLayout.pipFrame {
                CanvasDraggableElement(
                    frame: pipFrame,
                    canvasSize: canvasSize,
                    isSelected: selectedElement == .pip,
                    selectionCornerRadius: pipPreviewCornerRadius(
                        for: viewModel.currentCanvasLayout.pipShape,
                        frame: pipFrame,
                        in: canvasSize
                    ),
                    resizeMode: viewModel.currentCanvasLayout.pipShape == .rectangle ? .freeform : .squarePixels,
                    onSelect: {
                        selectedElement = .pip
                        screenCropMode = false  // 切换到 PiP 时退出裁剪模式
                    },
                    onFrameChange: { viewModel.updateCanvasPipFrame($0) }
                ) {
                    PiPVideoLayer(
                        viewModel: viewModel,
                        shape: viewModel.currentCanvasLayout.pipShape,
                        frame: pipFrame,
                        canvasSize: canvasSize,
                        cameraPlayer: cameraPlayer
                    )
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .contentShape(Rectangle())
        .onTapGesture { selectedElement = nil }
    }
}

// MARK: - 可拖移/缩放的画布元素

private struct CanvasDraggableElement<Content: View>: View {
    let frame: CanvasElementFrame
    let canvasSize: CGSize
    let isSelected: Bool
    var selectionCornerRadius: CGFloat = 8
    var resizeMode: CanvasResizeMode = .proportional
    let onSelect: () -> Void
    let onFrameChange: (CanvasElementFrame) -> Void
    @ViewBuilder let content: () -> Content

    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartFrame: CanvasElementFrame? = nil
    @State private var isResizing = false
    @State private var resizeStartFrame: CanvasElementFrame? = nil
    @State private var resizeStartLocation: CGPoint = .zero

    private var elementRect: CGRect { frame.toRect(in: canvasSize) }
    private var handleSize: CGFloat { 22 }

    var body: some View {
        let rect = elementRect
        ZStack(alignment: .bottomTrailing) {
            content()
                .frame(width: rect.width, height: rect.height)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: selectionCornerRadius, style: .continuous)
                            .stroke(Color.white, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }

            // 右下角缩放手柄
            if isSelected {
                resizeHandle
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartFrame = frame
                        onSelect()
                    }
                    guard let startFrame = dragStartFrame, canvasSize.width > 0, canvasSize.height > 0 else { return }
                    let newCX = startFrame.centerX + value.translation.width  / canvasSize.width
                    let newCY = startFrame.centerY + value.translation.height / canvasSize.height
                    let halfW = frame.widthRatio  / 2
                    let halfH = frame.heightRatio / 2
                    let clampedCX = min(max(newCX, halfW), 1 - halfW)
                    let clampedCY = min(max(newCY, halfH), 1 - halfH)
                    onFrameChange(CanvasElementFrame(
                        centerX: clampedCX,
                        centerY: clampedCY,
                        widthRatio: frame.widthRatio,
                        heightRatio: frame.heightRatio
                    ))
                }
                .onEnded { _ in isDragging = false }
        )
        .onTapGesture { onSelect() }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
            .shadow(radius: 3)
            .offset(x: handleSize / 2 - 2, y: handleSize / 2 - 2)
            .onHover { hovering in
                if hovering {
                    NSCursor.crosshair.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            resizeStartFrame = frame
                            resizeStartLocation = value.startLocation
                        }
                        guard let startFrame = resizeStartFrame,
                              canvasSize.width > 0, canvasSize.height > 0 else { return }
                        let resized = resizedCanvasElementFrame(
                            startFrame: startFrame,
                            canvasSize: canvasSize,
                            translation: value.translation,
                            mode: resizeMode
                        )
                        onFrameChange(resized)
                    }
                    .onEnded { _ in isResizing = false; resizeStartFrame = nil }
            )
    }
}

// MARK: - 可裁剪 & 可缩放的画布元素（屏幕录像专用）
//
// 交互设计：
//   普通模式（选中）：
//     · 内部拖拽       → 移动整个元素（frame 改变，content 随之移动）
//     · 四角白圆圈      → 等比 resize 整个元素
//     · 右上角 crop 按钮 → 切换到裁剪模式
//
//   裁剪模式：
//     · 内容层完全静止，不响应拖拽
//     · 四条深色遮罩带 + 亮色裁剪框浮在内容上方
//     · 拖拽任意一条边 → 只移动该边（裁剪框收缩/扩张）
//     · 拖拽四角 L 手柄 → 同时移动两条相邻边
//     · 再次点击 crop 按钮 或 点击画布外区域 → 退出裁剪模式

private enum CropEdge: Hashable { case top, bottom, leading, trailing }
private enum ResizeCorner: Hashable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

private struct CanvasCropableElement<Content: View>: View {
    let frame: CanvasElementFrame
    let crop: ScreenCropRect
    let canvasSize: CGSize
    let isSelected: Bool
    let isCropMode: Bool
    let onSelect: () -> Void
    let onCropModeChange: (Bool) -> Void
    let onFrameChange: (CanvasElementFrame) -> Void
    let onCropChange: (ScreenCropRect) -> Void
    @ViewBuilder let content: () -> Content

    // 拖移/resize 状态（普通模式）
    @State private var isDragging      = false
    @State private var dragStartFrame: CanvasElementFrame? = nil
    @State private var isResizing      = false
    @State private var resizeStartFrame: CanvasElementFrame? = nil

    // 裁剪状态（裁剪模式）
    @State private var isCropping      = false
    @State private var cropStart: ScreenCropRect = .full   // 拖拽开始时记录
    // 进入裁剪模式时，锁定完整视频在画布上的 Rect（保持视频画面静止的关键）
    @State private var lockedFullRect: CGRect? = nil

    private var elementRect: CGRect { frame.toRect(in: canvasSize) }
    private let cornerHandleSize: CGFloat = 14
    private let edgeHitThick: CGFloat     = 20   // 边缘热区厚度
    private let cornerHitSize: CGFloat    = 32   // 角热区尺寸

    // ── 完整源视频在画布上的 Rect ──
    // 裁剪模式下使用 lockedFullRect（进入时锁定，视频静止）
    // 普通模式下动态计算
    private var fullVideoRect: CGRect {
        if isCropMode, let locked = lockedFullRect { return locked }
        return computeFullVideoRect(from: frame)
    }

    private func computeFullVideoRect(from f: CanvasElementFrame) -> CGRect {
        let visible = f.toRect(in: canvasSize)
        return crop.contentRect(in: visible)
    }

    // ── 裁剪框在完整视频坐标系中的 Rect（= visible 区域）──
    private var cropBoxInFull: CGRect {
        let visible = frame.toRect(in: canvasSize)
        let full    = fullVideoRect
        // 裁剪框左上角相对于 fullVideoRect 左上角
        return CGRect(
            x: visible.minX - full.minX,
            y: visible.minY - full.minY,
            width:  visible.width,
            height: visible.height
        )
    }

    var body: some View {
        let rect = elementRect
        ZStack {
            if isCropMode {
                // ── 裁剪模式：外层容器已扩大到 fullVideoRect，视频完整显示 ──────
                let full = fullVideoRect
                let box  = cropBoxInFull

                // 完整视频内容（静止不动，填满扩大后的容器）
                content()
                    .frame(width: full.width, height: full.height)
                    .allowsHitTesting(false)

                // 裁剪覆盖层（暗色遮罩 + 亮色裁剪框 + 手柄，同样填满容器）
                if isSelected {
                    cropOverlay(fullSize: CGSize(width: full.width, height: full.height), box: box)
                }

                // 工具栏定位在原始 visible rect 上方（相对于扩大后容器的坐标）
                if isSelected {
                    let visibleInFull = cropBoxInFull  // 裁剪框坐标 = 可见区域在full中的位置
                    let toolbarRect = CGRect(
                        x: visibleInFull.minX, y: visibleInFull.minY,
                        width: visibleInFull.width, height: visibleInFull.height
                    )
                    cropToolbar(rect: toolbarRect)
                }

            } else {
                // ── 普通模式：按 screenFrame 大小显示 ────────────────────────
                content()
                    .frame(width: rect.width, height: rect.height)

                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .allowsHitTesting(false)

                    cornerResizeHandles(rect: rect)
                    cropToolbar(rect: rect)
                }
            }
        }
        // 裁剪模式下，外层容器扩大到完整视频大小，否则内层 offset 会被 clip
        .frame(
            width:  isCropMode ? fullVideoRect.width  : rect.width,
            height: isCropMode ? fullVideoRect.height : rect.height
        )
        .position(
            x: isCropMode ? fullVideoRect.midX : rect.midX,
            y: isCropMode ? fullVideoRect.midY : rect.midY
        )
        // 外部（如点击画布空白区域）将 isCropMode 强制改为 false 时，清除锁定
        .onChange(of: isCropMode) { _, newValue in
            if !newValue { lockedFullRect = nil }
        }
        // 内部拖拽 = 移动（裁剪模式下禁用）
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard !isCropMode, !isResizing else { return }
                    if !isDragging {
                        isDragging = true
                        dragStartFrame = frame
                        onSelect()
                    }
                    guard let startFrame = dragStartFrame,
                          canvasSize.width > 0, canvasSize.height > 0 else { return }
                    let newCX = startFrame.centerX + value.translation.width  / canvasSize.width
                    let newCY = startFrame.centerY + value.translation.height / canvasSize.height
                    let halfW = frame.widthRatio  / 2
                    let halfH = frame.heightRatio / 2
                    onFrameChange(CanvasElementFrame(
                        centerX: min(max(newCX, halfW), 1 - halfW),
                        centerY: min(max(newCY, halfH), 1 - halfH),
                        widthRatio: frame.widthRatio,
                        heightRatio: frame.heightRatio
                    ))
                }
                .onEnded { _ in isDragging = false }
        )
        .onTapGesture { onSelect() }
    }

    // MARK: - 裁剪覆盖层（图片静止，框在上面）

    /// 在完整源视频尺寸空间内，绘制暗色遮罩 + 亮色裁剪框 + 边缘手柄
    /// - fullSize: 完整视频在画布上的像素大小
    /// - box: 裁剪框在完整视频坐标系中的 rect（= 可见区域）
    @ViewBuilder
    private func cropOverlay(fullSize: CGSize, box: CGRect) -> some View {
        let fullRect = CGRect(origin: .zero, size: fullSize)
        ZStack {
            // 1. 四块暗色遮罩（盖住被裁掉的区域）
            cropDimMasks(box: box, rect: fullRect)

            // 2. 亮色裁剪框线
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
                .allowsHitTesting(false)

            // 3. 三等分网格（辅助构图）
            cropGrid(box: box)
                .allowsHitTesting(false)

            // 4. 四条边的热区手柄
            ForEach([CropEdge.top, .bottom, .leading, .trailing], id: \.self) { edge in
                cropEdgeHandle(edge: edge, box: box, rect: fullRect)
            }

            // 5. 四角 L 型手柄
            ForEach([ResizeCorner.topLeading, .topTrailing, .bottomLeading, .bottomTrailing], id: \.self) { corner in
                cropCornerHandle(corner: corner, box: box, rect: fullRect)
            }
        }
        .frame(width: fullSize.width, height: fullSize.height)
        .allowsHitTesting(true)
    }

    /// 四块暗色遮罩
    @ViewBuilder
    private func cropDimMasks(box: CGRect, rect: CGRect) -> some View {
        let dimColor = Color.black.opacity(0.55)
        // top
        if box.minY > 0 {
            Rectangle().fill(dimColor)
                .frame(width: rect.width, height: max(0, box.minY))
                .position(x: rect.width / 2, y: box.minY / 2)
        }
        // bottom
        if box.maxY < rect.height {
            Rectangle().fill(dimColor)
                .frame(width: rect.width, height: max(0, rect.height - box.maxY))
                .position(x: rect.width / 2, y: (box.maxY + rect.height) / 2)
        }
        // left
        if box.minX > 0 {
            Rectangle().fill(dimColor)
                .frame(width: max(0, box.minX), height: box.height)
                .position(x: box.minX / 2, y: box.midY)
        }
        // right
        if box.maxX < rect.width {
            Rectangle().fill(dimColor)
                .frame(width: max(0, rect.width - box.maxX), height: box.height)
                .position(x: (box.maxX + rect.width) / 2, y: box.midY)
        }
    }

    /// 三等分构图网格
    @ViewBuilder
    private func cropGrid(box: CGRect) -> some View {
        let lineColor = Color.white.opacity(0.3)
        let lw: CGFloat = 0.5
        // 竖线
        Path { p in
            p.move(to: CGPoint(x: box.minX + box.width / 3, y: box.minY))
            p.addLine(to: CGPoint(x: box.minX + box.width / 3, y: box.maxY))
            p.move(to: CGPoint(x: box.minX + box.width * 2 / 3, y: box.minY))
            p.addLine(to: CGPoint(x: box.minX + box.width * 2 / 3, y: box.maxY))
        }
        .stroke(lineColor, lineWidth: lw)
        // 横线
        Path { p in
            p.move(to: CGPoint(x: box.minX, y: box.minY + box.height / 3))
            p.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height / 3))
            p.move(to: CGPoint(x: box.minX, y: box.minY + box.height * 2 / 3))
            p.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * 2 / 3))
        }
        .stroke(lineColor, lineWidth: lw)
    }

    // MARK: - 边缘拖拽手柄（只移动裁剪框那条边）

    private func cropEdgeHandle(edge: CropEdge, box: CGRect, rect: CGRect) -> some View {
        let isVert = edge == .top || edge == .bottom
        let hitW: CGFloat = isVert ? box.width : edgeHitThick
        let hitH: CGFloat = isVert ? edgeHitThick : box.height

        // 视觉短线（中间 1/3）
        let visW: CGFloat = isVert ? min(box.width * 0.3, 60) : 3
        let visH: CGFloat = isVert ? 3 : min(box.height * 0.3, 60)

        let pos: CGPoint = {
            switch edge {
            case .top:      return CGPoint(x: box.midX, y: box.minY)
            case .bottom:   return CGPoint(x: box.midX, y: box.maxY)
            case .leading:  return CGPoint(x: box.minX, y: box.midY)
            case .trailing: return CGPoint(x: box.maxX, y: box.midY)
            }
        }()

        return ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: visW, height: visH)
                .shadow(color: .black.opacity(0.35), radius: 2)
                .allowsHitTesting(false)
        }
        .frame(width: hitW, height: hitH)
        .contentShape(Rectangle())
        .position(pos)
        .onHover { hovering in
            if hovering {
                if isVert { NSCursor.resizeUpDown.push() }
                else      { NSCursor.resizeLeftRight.push() }
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !isCropping { isCropping = true; cropStart = crop }
                    applyCropEdge(edge: edge, gesture: g, elementRect: rect)
                }
                .onEnded { _ in isCropping = false }
        )
    }

    /// 根据新的 crop 和锁定的 fullVideoRect，反算出对应的 screenFrame 并通知上层
    /// 这样 fullVideoRect 保持不变（视频静止），只有裁剪框（可见区域）在动
    private func applyCropAndSyncFrame(_ newCrop: ScreenCropRect) {
        guard let full = lockedFullRect, canvasSize.width > 0, canvasSize.height > 0 else {
            onCropChange(newCrop)
            return
        }
        // 反算：可见区域在画布上的大小和位置
        let visW = newCrop.width  * full.width
        let visH = newCrop.height * full.height
        let visX = full.minX + newCrop.minX * full.width
        let visY = full.minY + newCrop.minY * full.height
        // 换算为 CanvasElementFrame（归一化比例）
        let newFrame = CanvasElementFrame(
            centerX:     (visX + visW / 2) / canvasSize.width,
            centerY:     (visY + visH / 2) / canvasSize.height,
            widthRatio:  visW / canvasSize.width,
            heightRatio: visH / canvasSize.height
        )
        onCropChange(newCrop)
        onFrameChange(newFrame)
    }

    /// 只移动裁剪框的单条边（图片完全静止，frame 同步更新使视频不动）
    private func applyCropEdge(edge: CropEdge, gesture: DragGesture.Value, elementRect: CGRect) {
        // elementRect 是锁定的完整源视频在画布上的大小，宽度 = 1.0（源视频全宽）
        let pxToSrcW = 1.0 / max(elementRect.width,  1)
        let pxToSrcH = 1.0 / max(elementRect.height, 1)

        var c = cropStart

        switch edge {
        case .top:
            // 向下拖 dy>0：裁掉上边更多，minY 增大，height 减小
            let dy = gesture.translation.height * pxToSrcH
            c.minY  = min(max(cropStart.minY + dy, 0), cropStart.minY + cropStart.height - 0.05)
            c.height = cropStart.height - (c.minY - cropStart.minY)
        case .bottom:
            // 向下拖 dy>0：下边扩展，height 增大
            let dy = gesture.translation.height * pxToSrcH
            c.height = min(max(cropStart.height + dy, 0.05), 1 - cropStart.minY)
        case .leading:
            // 向右拖 dx>0：裁掉左边更多，minX 增大，width 减小
            let dx = gesture.translation.width * pxToSrcW
            c.minX  = min(max(cropStart.minX + dx, 0), cropStart.minX + cropStart.width - 0.05)
            c.width = cropStart.width - (c.minX - cropStart.minX)
        case .trailing:
            // 向右拖 dx>0：右边扩展，width 增大
            let dx = gesture.translation.width * pxToSrcW
            c.width = min(max(cropStart.width + dx, 0.05), 1 - cropStart.minX)
        }

        // 同步更新 screenFrame，保持完整视频 rect 不变（视频静止，只有裁剪框动）
        applyCropAndSyncFrame(c)
    }

    // MARK: - 角拖拽手柄（同时移动两条相邻边）

    private func cropCornerHandle(corner: ResizeCorner, box: CGRect, rect: CGRect) -> some View {
        let len: CGFloat  = 22
        let lineW: CGFloat = 3
        let hitSize = cornerHitSize

        let pos: CGPoint = {
            switch corner {
            case .topLeading:     return CGPoint(x: box.minX, y: box.minY)
            case .topTrailing:    return CGPoint(x: box.maxX, y: box.minY)
            case .bottomLeading:  return CGPoint(x: box.minX, y: box.maxY)
            case .bottomTrailing: return CGPoint(x: box.maxX, y: box.maxY)
            }
        }()

        return ZStack {
            Path { path in
                switch corner {
                case .topLeading:
                    path.move(to: CGPoint(x: 0, y: len))
                    path.addLine(to: .zero)
                    path.addLine(to: CGPoint(x: len, y: 0))
                case .topTrailing:
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: len, y: 0))
                    path.addLine(to: CGPoint(x: len, y: len))
                case .bottomLeading:
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: len))
                    path.addLine(to: CGPoint(x: len, y: len))
                case .bottomTrailing:
                    path.move(to: CGPoint(x: 0, y: len))
                    path.addLine(to: CGPoint(x: len, y: len))
                    path.addLine(to: CGPoint(x: len, y: 0))
                }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: lineW, lineCap: .square))
            .frame(width: len, height: len)
            .shadow(color: .black.opacity(0.35), radius: 2)
            .allowsHitTesting(false)
        }
        .frame(width: hitSize, height: hitSize)
        .contentShape(Rectangle())
        .position(pos)
        .onHover { hovering in
            if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !isCropping { isCropping = true; cropStart = crop }
                    applyCropCorner(corner: corner, gesture: g, elementRect: rect)
                }
                .onEnded { _ in isCropping = false }
        )
    }

    private func applyCropCorner(corner: ResizeCorner, gesture: DragGesture.Value, elementRect: CGRect) {
        // 新架构：elementRect 是完整源视频在画布上的大小，宽度 = 1.0（源视频全宽）
        let pxToSrcW = 1.0 / max(elementRect.width,  1)
        let pxToSrcH = 1.0 / max(elementRect.height, 1)
        let dx = gesture.translation.width  * pxToSrcW
        let dy = gesture.translation.height * pxToSrcH
        var c = cropStart

        switch corner {
        case .topLeading:
            c.minX   = min(max(cropStart.minX + dx, 0), cropStart.minX + cropStart.width  - 0.05)
            c.width  = cropStart.width  - (c.minX - cropStart.minX)
            c.minY   = min(max(cropStart.minY + dy, 0), cropStart.minY + cropStart.height - 0.05)
            c.height = cropStart.height - (c.minY - cropStart.minY)
        case .topTrailing:
            c.width  = min(max(cropStart.width + dx, 0.05), 1 - cropStart.minX)
            c.minY   = min(max(cropStart.minY + dy, 0), cropStart.minY + cropStart.height - 0.05)
            c.height = cropStart.height - (c.minY - cropStart.minY)
        case .bottomLeading:
            c.minX   = min(max(cropStart.minX + dx, 0), cropStart.minX + cropStart.width  - 0.05)
            c.width  = cropStart.width  - (c.minX - cropStart.minX)
            c.height = min(max(cropStart.height + dy, 0.05), 1 - cropStart.minY)
        case .bottomTrailing:
            c.width  = min(max(cropStart.width + dx, 0.05), 1 - cropStart.minX)
            c.height = min(max(cropStart.height + dy, 0.05), 1 - cropStart.minY)
        }

        applyCropAndSyncFrame(c)
    }

    // MARK: - 普通模式四角 Resize 手柄

    private func cornerResizeHandles(rect: CGRect) -> some View {
        let corners: [ResizeCorner] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
        return ZStack {
            ForEach(corners, id: \.self) { corner in
                cornerResizeHandle(corner: corner, rect: rect)
            }
        }
    }

    private func cornerResizeHandle(corner: ResizeCorner, rect: CGRect) -> some View {
        let hs = cornerHandleSize
        let pos: CGPoint = {
            switch corner {
            case .topLeading:     return CGPoint(x: 0, y: 0)
            case .topTrailing:    return CGPoint(x: rect.width, y: 0)
            case .bottomLeading:  return CGPoint(x: 0, y: rect.height)
            case .bottomTrailing: return CGPoint(x: rect.width, y: rect.height)
            }
        }()
        return Circle()
            .fill(Color.white)
            .frame(width: hs, height: hs)
            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 3)
            .position(pos)
            .onHover { hovering in
                if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isDragging, !isCropping else { return }
                        if !isResizing {
                            isResizing = true
                            resizeStartFrame = frame
                        }
                        applyCornerResize(corner: corner, gesture: value)
                    }
                    .onEnded { _ in isResizing = false; resizeStartFrame = nil }
            )
    }

    private func applyCornerResize(corner: ResizeCorner, gesture: DragGesture.Value) {
        guard let startFrame = resizeStartFrame,
              canvasSize.width > 0, canvasSize.height > 0 else { return }
        let dx = gesture.translation.width  / canvasSize.width
        let _  = gesture.translation.height / canvasSize.height  // dy unused (aspect-ratio resize uses only dx)
        let left0   = startFrame.centerX - startFrame.widthRatio  / 2
        let right0  = startFrame.centerX + startFrame.widthRatio  / 2
        let top0    = startFrame.centerY - startFrame.heightRatio / 2
        let bottom0 = startFrame.centerY + startFrame.heightRatio / 2
        let aspect  = startFrame.widthRatio / max(startFrame.heightRatio, 0.001)
        let minSize: Double = 0.05
        var left = left0, right = right0, top = top0, bottom = bottom0
        switch corner {
        case .topLeading:
            let newW = max(minSize, right0 - (left0 + dx))
            left = right0 - newW; top = bottom0 - newW / aspect
        case .topTrailing:
            let newW = max(minSize, (right0 + dx) - left0)
            right = left0 + newW; top = bottom0 - newW / aspect
        case .bottomLeading:
            let newW = max(minSize, right0 - (left0 + dx))
            left = right0 - newW; bottom = top0 + newW / aspect
        case .bottomTrailing:
            let newW = max(minSize, (right0 + dx) - left0)
            right = left0 + newW; bottom = top0 + newW / aspect
        }
        left = max(0, left); right = min(1, right)
        top  = max(0, top);  bottom = min(1, bottom)
        let newW = right - left; let newH = bottom - top
        guard newW >= minSize, newH >= minSize else { return }
        onFrameChange(CanvasElementFrame(
            centerX: left + newW / 2, centerY: top + newH / 2,
            widthRatio: newW, heightRatio: newH
        ))
    }

    // MARK: - 工具栏

    /// - rect: 在当前容器坐标系中，按钮应出现的参考矩形（工具栏放在它正上方）
    /// - useMidX: 若为 false，按钮 X = rect.midX（用于裁剪模式下的绝对坐标）
    private func cropToolbar(rect: CGRect) -> some View {
        HStack(spacing: 6) {
            Button(action: {
            if !isCropMode {
                // 进入裁剪模式：锁定当前完整视频 Rect，保持视频静止
                lockedFullRect = computeFullVideoRect(from: frame)
            } else {
                // 退出裁剪模式：清除锁定
                lockedFullRect = nil
            }
            onCropModeChange(!isCropMode)
        }) {
                HStack(spacing: 4) {
                    Image(systemName: isCropMode ? "crop.fill" : "crop")
                        .font(.system(size: 12, weight: .medium))
                    Text(isCropMode ? "完成" : "裁剪")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isCropMode ? Color.yellow : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.78))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        // position 在父容器坐标系中：工具栏在 rect 的水平中心，上方 22pt
        .position(x: rect.midX, y: rect.minY - 22)
    }
}

// MARK: - 背景视图

private struct CanvasBackgroundView: View {
    let background: CanvasBackground

    var body: some View {
        switch background {
        case let .solidColor(r, g, b, a):
            Color(red: r, green: g, blue: b, opacity: a)
        case let .linearGradient(r1, g1, b1, r2, g2, b2, _):
            let points = background.gradientPointsForSwiftUI()
            LinearGradient(
                colors: [
                    Color(red: r1, green: g1, blue: b1),
                    Color(red: r2, green: g2, blue: b2)
                ],
                startPoint: UnitPoint(points?.start ?? CGPoint(x: 0, y: 0)),
                endPoint:   UnitPoint(points?.end ?? CGPoint(x: 1, y: 1))
            )
        case let .image(path):
            if let nsImage = NSImage(contentsOfFile: path) {
                GeometryReader { geo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                Color.black
            }
        }
    }
}

private extension UnitPoint {
    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }
}

// MARK: - 屏幕录像层（画布内）

private struct ScreenVideoLayer: View {
    let viewModel: AppViewModel
    let player: AVPlayer?
    var baseCrop: ScreenCropRect = .full

    @State private var localPlaybackPositionSeconds: Double = 0

    private var resolvedCrop: ScreenCropRect {
        guard viewModel.smartAutoZoomSettings.isEnabled else { return baseCrop }
        return viewModel.playbackScreenCrop(baseCrop: baseCrop, at: localPlaybackPositionSeconds)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let player {
                    let fullRect = resolvedCrop.contentRect(in: CGRect(origin: .zero, size: geo.size))

                    SharedPlayerView(
                        player: player,
                        playbackState: viewModel.playbackState,
                        trimEndSeconds: viewModel.trimEndSeconds,
                        onPositionChange: viewModel.updatePlaybackPosition,
                        onSmoothPositionChange: { localPlaybackPositionSeconds = $0 },
                        onPlaybackFinished: viewModel.handlePlaybackFinished
                    )
                    .frame(width: fullRect.width, height: fullRect.height)
                    .offset(x: fullRect.minX, y: fullRect.minY)
                    .clipped()
                } else if viewModel.latestRecording != nil {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white.opacity(0.5))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("屏幕录像")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
        .clipped()
        .onAppear { localPlaybackPositionSeconds = viewModel.playbackPositionSeconds }
        .onChange(of: viewModel.playbackPositionSeconds) { _, newValue in
            // 播放时由 onSmoothPositionChange 以 30fps 驱动（两者值相同，无冲突）；
            // seek/scrubbing 时 onSmoothPositionChange 不会立即触发，
            // 必须在这里无条件同步，否则 auto-zoom 预览会停留在旧帧。
            localPlaybackPositionSeconds = newValue
        }
    }
}

// MARK: - PiP 摄像头层（画布内）

private struct PiPVideoLayer: View {
    let viewModel: AppViewModel
    let shape: CameraShape
    let frame: CanvasElementFrame
    let canvasSize: CGSize
    let cameraPlayer: AVPlayer?

    private var cornerRadius: CGFloat {
        pipPreviewCornerRadius(for: shape, frame: frame, in: canvasSize)
    }

    var body: some View {
        ZStack {
            if let player = cameraPlayer {
                // 有真实摄像头录像时直接播放
                SharedPlayerView(
                    player: player,
                    playbackState: viewModel.playbackState,
                    onPositionChange: { _ in },    // PiP 跟随 screen player 同步，无需单独回调
                    onSmoothPositionChange: { _ in },
                    onPlaybackFinished: viewModel.handlePlaybackFinished
                )
            } else if viewModel.latestRecording != nil {
                // 录制完成但没有独立摄像头文件（合并录制模式下的占位符）
                Color(red: 0.15, green: 0.15, blue: 0.18)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("摄像头")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
            } else {
                Color(red: 0.15, green: 0.15, blue: 0.18)
                    .overlay {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
        )
    }
}

// MARK: - 右侧面板

struct SmartAutoZoomControlModel: Identifiable {
    let title: String
    let keyPath: WritableKeyPath<SmartAutoZoomSettings, Double>
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let value: Double

    var id: String { title }
    var formattedValue: String { String(format: format, value) }
}

func makeSmartAutoZoomControlModels(settings: SmartAutoZoomSettings) -> [SmartAutoZoomControlModel] {
    guard settings.isEnabled else { return [] }

    return [
        SmartAutoZoomControlModel(
            title: "放大倍数",
            keyPath: \.zoomScale,
            range: 1.2...3,
            step: 0.1,
            format: "%.1fx",
            value: settings.zoomScale
        ),
        SmartAutoZoomControlModel(
            title: "进入时长",
            keyPath: \.leadInSeconds,
            range: 0.05...0.5,
            step: 0.05,
            format: "%.2fs",
            value: settings.leadInSeconds
        ),
        SmartAutoZoomControlModel(
            title: "停留时长",
            keyPath: \.holdSeconds,
            range: 0.2...1.5,
            step: 0.05,
            format: "%.2fs",
            value: settings.holdSeconds
        ),
        SmartAutoZoomControlModel(
            title: "退出时长",
            keyPath: \.releaseSeconds,
            range: 0.1...0.8,
            step: 0.05,
            format: "%.2fs",
            value: settings.releaseSeconds
        )
    ]
}

private struct StudioSidePanel: View {
    @Bindable var viewModel: AppViewModel
    let sharedPlayer: AVPlayer?
    var cameraPlayer: AVPlayer? = nil
    @State private var trimMode = false
    @State private var showImagePicker = false
    @State private var showCustomColorPopover = false
    @State private var customColorSelection = StudioCustomColorSelection()
    @State private var activeToast: ExportToastModel?
    @State private var toastTask: Task<Void, Never>? = nil
    @State private var showNewRecordingAlert = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // 平台选择
                    platformSection

                    // 背景编辑
                    backgroundSection

                    // PiP 控制
                    pipSection

                    // 播放控制
                    if viewModel.latestRecording != nil {
                        playbackSection
                        autoZoomSection
                    }

                    // 录制信息
                    recordingInfoSection
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footerActionSection
        }
        .padding(14)
        .background(panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 24, y: 10)
        .frame(maxHeight: .infinity)
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                viewModel.updateCanvasBackground(.image(path: url.path))
            }
        }
        .overlay(alignment: .bottom) {
            if let activeToast {
                exportToastView(activeToast)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: activeToast != nil)
        .onAppear { syncCustomColorSelection() }
        .onChange(of: viewModel.selectedPlatform) { _, _ in syncCustomColorSelection() }
        .onChange(of: viewModel.currentCanvasLayout.background) { _, _ in syncCustomColorSelection() }
        .onChange(of: viewModel.exportState) { _, newValue in
            showToastIfNeeded(makeVariantExportToastModel(newValue))
        }
        .onChange(of: viewModel.sourceExportState) { _, newValue in
            showToastIfNeeded(makeSourceExportToastModel(newValue))
        }
        .onDisappear {
            toastTask?.cancel()
            toastTask = nil
        }
    }

    // MARK: 平台
    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("分发格式")
            ForEach(PlatformKind.allCases) { platform in
                PlatformExportRow(
                    platform: platform,
                    isSelected: viewModel.exportSelection.isEnabled(platform),
                    isCurrentCanvas: viewModel.selectedPlatform == platform,
                    exportResult: viewModel.exportedVariantsByPlatform[platform]
                ) {
                    viewModel.toggleExportVariant(platform)
                } onSelectCanvas: {
                    viewModel.select(platform: platform)
                }
            }
        }
        .padding(14)
        .background(cardBG)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
    }

    // MARK: 背景
    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("背景")

            HStack(spacing: 8) {
                customColorTrigger

                ForEach(CanvasBackground.studioPresets, id: \.label) { preset in
                    Button {
                        viewModel.updateCanvasBackground(preset.background)
                    } label: {
                        preset.previewSwatch
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(Color.white.opacity(0.8), lineWidth: 1)
                            }
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.92), lineWidth: 2)
                                    .padding(-4)
                                    .opacity(isCurrentBG(preset.background) ? 1 : 0)
                            }
                            .shadow(color: .black.opacity(isCurrentBG(preset.background) ? 0.14 : 0.08), radius: isCurrentBG(preset.background) ? 8 : 5, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                secondaryActionButton(icon: "photo", label: imageActionLabel, isActive: imageActionIsActive) {
                    showImagePicker = true
                }
                secondaryActionButton(icon: "arrow.counterclockwise", label: "重置") {
                    viewModel.resetCanvasLayout()
                }
            }
        }
        .padding(14)
        .background(cardBG)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
    }

    // MARK: PiP 控制
    private var pipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("画中画")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.currentCanvasLayout.pipFrame != nil },
                    set: { enabled in
                        if enabled {
                            let pipW: Double = 0.28
                            let defaultPip = CanvasElementFrame(
                                centerX: 0.78,
                                centerY: 0.82,
                                widthRatio: pipW,
                                heightRatio: pipW * Double(viewModel.selectedPlatform.aspectRatio)
                            ).normalizedForShape(
                                viewModel.currentCanvasLayout.pipShape,
                                platformAspectRatio: viewModel.selectedPlatform.aspectRatio
                            )
                            viewModel.updateCanvasPipFrame(defaultPip)
                        } else {
                            viewModel.updateCanvasPipFrame(nil)
                        }
                    }
                ))
                .scaleEffect(0.8)
                .labelsHidden()
            }

            if viewModel.currentCanvasLayout.pipFrame != nil {
                // 形状选择
                HStack(spacing: 8) {
                    ForEach(CameraShape.allCases, id: \.rawValue) { shape in
                        Button {
                            viewModel.updateCanvasPipShape(shape)
                        } label: {
                            Text(shape.iconLabel)
                                .font(.system(size: 18))
                                .frame(width: 36, height: 32)
                                .background(
                                    viewModel.currentCanvasLayout.pipShape == shape
                                    ? Color.black.opacity(0.12)
                                    : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(cardBG)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
    }

    // MARK: 播放控制
    private var playbackSection: some View {
        VStack(spacing: 10) {
            // 时间标签 + Slider
            HStack(spacing: 8) {
                Text(viewModel.formatPlaybackTime(viewModel.playbackPositionSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.45))

                Slider(
                    value: Binding(
                        get: { viewModel.playbackProgress },
                        set: { progress in
                            viewModel.seekPlayback(toProgress: progress)
                            let secs = viewModel.playbackDurationSeconds * progress
                            let time = CMTime(seconds: secs, preferredTimescale: 600)
                            sharedPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                            cameraPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                    ),
                    in: 0...1
                )

                Text(viewModel.formatPlaybackTime(viewModel.playbackDurationSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.45))
            }

            // 控制按钮
            HStack(spacing: 8) {
                Button {
                    viewModel.updatePlaybackPosition(seconds: 0)
                    viewModel.playbackState = .playing
                    let time = CMTime.zero
                    sharedPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                    cameraPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                } label: {
                    Image(systemName: "backward.end.fill").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Color.black.opacity(0.06))
                .clipShape(Circle())

                Button {
                    switch playbackPrimaryAction(for: viewModel) {
                    case .togglePlayback:
                        viewModel.togglePlayback()
                    case .restartFromBeginning:
                        viewModel.updatePlaybackPosition(seconds: 0)
                        viewModel.playbackState = .playing
                        let time = CMTime.zero
                        sharedPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                        cameraPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                } label: {
                    Image(systemName: playbackPrimaryButtonSymbol(for: viewModel))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .padding(7)
                .background(Color.black)
                .foregroundStyle(.white)
                .clipShape(Circle())

                Spacer()
            }
        }
        .padding(14)
        .background(cardBG)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
    }

    // MARK: Smart Auto-Zoom
    private var autoZoomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Smart Auto-Zoom")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.smartAutoZoomSettings.isEnabled },
                    set: { viewModel.smartAutoZoomSettings.isEnabled = $0; viewModel.savePreferences() }
                ))
                .scaleEffect(0.8)
                .labelsHidden()
            }

            if viewModel.smartAutoZoomSettings.isEnabled {
                ForEach(makeSmartAutoZoomControlModels(settings: viewModel.smartAutoZoomSettings)) { control in
                    sliderRow(
                        title: control.title,
                        value: Binding(
                            get: { viewModel.smartAutoZoomSettings[keyPath: control.keyPath] },
                            set: { viewModel.smartAutoZoomSettings[keyPath: control.keyPath] = $0; viewModel.savePreferences() }
                        ),
                        range: control.range,
                        step: control.step,
                        format: control.format
                    )
                }
            }
        }
        .padding(14)
        .background(cardBG)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
    }

    // MARK: 录制信息
    private var recordingInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("录制信息")
            infoRow("时长", viewModel.totalPlaybackTimeLabel)
            infoRow("大小", recordingFileSize)
        }
        .padding(14)
        .background(cardBG)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 3)
    }

    // MARK: 导出状态
    @ViewBuilder
    private var exportStatusSection: some View {
        VStack(spacing: 10) {
            if case .exporting = viewModel.exportState {
                statusLoadingCard(
                    title: "正在导出成片",
                    message: "保持当前窗口打开，导出完成后可直接定位文件"
                )
            }

            if let card = makeVariantExportStatusCardModel(viewModel.exportState) {
                ExportStatusSummaryCard(model: card) { item in
                    openFileInFinder(item.fileURL)
                }
            }

            if case .exporting = viewModel.sourceExportState {
                statusLoadingCard(
                    title: "正在整理原素材",
                    message: "会保留 screen / camera 两份文件，方便后续精修"
                )
            }

            if let card = makeSourceExportStatusCardModel(viewModel.sourceExportState) {
                ExportStatusSummaryCard(model: card) { item in
                    openFileInFinder(item.fileURL)
                }
            }
        }
    }

    private var footerActionSection: some View {
        VStack(spacing: 10) {
            exportStatusSection
            newRecordingButton
            exportButton
        }
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(height: 1)
                .padding(.top, -6)
                .opacity(0.35)
        }
    }

    private var newRecordingButton: some View {
        VStack(spacing: 8) {
            // 主按钮
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    showNewRecordingAlert.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showNewRecordingAlert ? "chevron.down.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("新建录制")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color(red: 0.84, green: 0.89, blue: 0.99))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.68), lineWidth: 1)
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color(red: 0.52, green: 0.60, blue: 0.92).opacity(0.18), radius: 10, y: 4)
            }
            .buttonStyle(.plain)

            // Inline 确认卡（展开/收起）
            if showNewRecordingAlert {
                VStack(alignment: .leading, spacing: 10) {
                    Text("当前编辑内容不会自动保存")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                showNewRecordingAlert = false
                            }
                        } label: {
                            Text("取消")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.52))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                                }
                                .foregroundStyle(Color.black.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                showNewRecordingAlert = false
                            }
                            viewModel.startNewRecording()
                        } label: {
                            Text("确认新建")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.black.opacity(0.82))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.62))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
    }

    // MARK: 导出按钮
    private var exportButton: some View {
        HStack(spacing: 10) {
            Button {
                Task { await viewModel.exportSourceAssets() }
            } label: {
                Text(sourceExportButtonTitle)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(isExporting ? 0.18 : 0.26))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    }
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isExporting || viewModel.latestRecording == nil)

            Button {
                Task { await viewModel.exportSelectedVariants() }
            } label: {
                HStack {
                    if case .exporting = viewModel.exportState {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    }
                    Text(exportButtonTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isExporting ? Color.black.opacity(0.52) : Color.black.opacity(0.9))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: isExporting ? 0 : 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isExporting || viewModel.currentPreviewFileURL == nil)
        }
    }

    // MARK: Helpers
    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.14))
            }
    }

    private var cardBG: some View {
        Color.white.opacity(0.32)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.system(size: 12))
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            Slider(value: value, in: range, step: step)
                .tint(Color.black)
        }
    }

    private var customColorTrigger: some View {
        Button(action: openCustomColorPopover) {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(customColorTriggerBaseColor)
                    .overlay {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [.purple, .pink, .orange, .yellow, .green, .cyan, .blue, .purple],
                                    center: .center
                                ),
                                lineWidth: 2.5
                            )
                    }
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(isUsingCustomColor ? 0.12 : 0.06), radius: isUsingCustomColor ? 7 : 4, y: 2)

                Circle()
                    .fill(Color.white.opacity(0.98))
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.14), radius: 4, y: 1)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }
                    .offset(x: -2, y: -2)
            }
            .frame(width: 34, height: 34)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.92), lineWidth: 2)
                    .padding(-2)
                    .opacity((isUsingCustomColor || showCustomColorPopover) ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("自定义颜色")
        .popover(isPresented: $showCustomColorPopover, arrowEdge: .leading) {
            StudioCustomColorPopover(selection: customColorSelectionBinding)
                .padding(14)
                .frame(width: 262)
        }
    }

    private func secondaryActionButton(icon: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isActive ? Color.white.opacity(0.34) : Color.white.opacity(0.24))
            .overlay {
                Capsule().stroke(Color.white.opacity(isActive ? 0.62 : 0.5), lineWidth: 1)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func statusLoadingCard(title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(width: 34, height: 34)
                ProgressView()
                    .controlSize(.small)
                    .tint(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.54))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.26))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.48), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func openFileInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @ViewBuilder
    private func exportToastView(_ model: ExportToastModel) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: 26, height: 26)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.74))
            }

            Text(model.message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(model.actionTitle) {
                openFileInFinder(model.targetURL)
                dismissToast()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.62))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.56), lineWidth: 1)
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }

    private func showToastIfNeeded(_ model: ExportToastModel?) {
        guard let model else { return }
        toastTask?.cancel()
        activeToast = model
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        activeToast = nil
    }

    private var customColorSelectionBinding: Binding<StudioCustomColorSelection> {
        Binding(
            get: { customColorSelection },
            set: { selection in
                customColorSelection = selection
                applyCustomColorSelection(selection)
            }
        )
    }

    private func openCustomColorPopover() {
        syncCustomColorSelection()
        showCustomColorPopover = true
    }

    private func syncCustomColorSelection() {
        guard viewModel.currentCanvasLayout.background.isStudioCustomColor,
              let selection = StudioCustomColorSelection(background: viewModel.currentCanvasLayout.background) else {
            return
        }
        customColorSelection = selection
    }

    private func applyCustomColorSelection(_ selection: StudioCustomColorSelection) {
        viewModel.updateCanvasBackground(selection.canvasBackground)
    }

    private func isCurrentBG(_ bg: CanvasBackground) -> Bool {
        viewModel.currentCanvasLayout.background == bg
    }

    private var isUsingCustomColor: Bool {
        viewModel.currentCanvasLayout.background.isStudioCustomColor
    }

    private var customColorTriggerBaseColor: Color {
        customColorSelection.swiftUIColor
    }

    private var imageActionIsActive: Bool {
        if case .image = viewModel.currentCanvasLayout.background {
            return true
        }
        return false
    }

    private var imageActionLabel: String {
        imageActionIsActive ? "更换图片" : "图片"
    }

    private var recordingFileSize: String {
        guard let bytes = viewModel.latestRecording?.fileSizeBytes else { return "--" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var isExporting: Bool {
        if case .exporting = viewModel.exportState { return true }
        if case .exporting = viewModel.sourceExportState { return true }
        return false
    }

    private var exportButtonTitle: String {
        if case .exporting = viewModel.exportState { return "导出中..." }
        return "导出"
    }

    private var sourceExportButtonTitle: String {
        if case .exporting = viewModel.sourceExportState { return "素材导出中..." }
        return "原素材"
    }
}

// MARK: - Studio Custom Color Popover

private struct StudioCustomColorPopover: View {
    @Binding var selection: StudioCustomColorSelection

    private let quickSelections: [StudioCustomColorSelection] = [
        .init(hue: 0.01, saturation: 0.74, brightness: 0.99),
        .init(hue: 0.09, saturation: 0.82, brightness: 1.0),
        .init(hue: 0.16, saturation: 0.72, brightness: 1.0),
        .init(hue: 0.28, saturation: 0.58, brightness: 0.94),
        .init(hue: 0.46, saturation: 0.62, brightness: 0.92),
        .init(hue: 0.58, saturation: 0.47, brightness: 0.98),
        .init(hue: 0.74, saturation: 0.50, brightness: 0.96),
        .init(hue: 0.90, saturation: 0.42, brightness: 0.98)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自定义颜色")
                        .font(.system(size: 14, weight: .semibold))
                    Text("纯色")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.06))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                Text(selection.hexString)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.78))
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    }
                    .clipShape(Capsule())
            }

            StudioColorSpectrumField(selection: $selection)
                .frame(height: 154)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("色相")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(selection.hue * 360))°")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                StudioHueSlider(selection: $selection)
                    .frame(height: 18)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("快捷色")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(Array(quickSelections.enumerated()), id: \.offset) { _, quickSelection in
                        Button {
                            selection = quickSelection
                        } label: {
                            Circle()
                                .fill(quickSelection.swiftUIColor)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Circle()
                                        .stroke(Color.white.opacity(0.88), lineWidth: 1)
                                }
                                .overlay {
                                    Circle()
                                        .stroke(Color.black.opacity(0.78), lineWidth: 1.5)
                                        .padding(-3)
                                        .opacity(distance(from: quickSelection, to: selection) < 0.04 ? 1 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.2))
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.52), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    private func distance(from lhs: StudioCustomColorSelection, to rhs: StudioCustomColorSelection) -> Double {
        abs(lhs.hue - rhs.hue) + abs(lhs.saturation - rhs.saturation) + abs(lhs.brightness - rhs.brightness)
    }
}

private struct StudioColorSpectrumField: View {
    @Binding var selection: StudioCustomColorSelection

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = max(geometry.size.height, 1)
            let indicatorX = selection.saturation * width
            let indicatorY = (1 - selection.brightness) * height

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hue: selection.hue, saturation: 1, brightness: 1))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.56), lineWidth: 1)

                Circle()
                    .fill(selection.swiftUIColor)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.96), lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
                    .position(x: min(max(indicatorX, 10), width - 10), y: min(max(indicatorY, 10), height - 10))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, 0), width)
                        let y = min(max(value.location.y, 0), height)
                        selection.saturation = x / width
                        selection.brightness = 1 - (y / height)
                    }
            )
        }
    }
}

private struct StudioHueSlider: View {
    @Binding var selection: StudioCustomColorSelection

    private let sliderGradient = LinearGradient(
        colors: [
            Color(hue: 0.0, saturation: 1, brightness: 1),
            Color(hue: 0.17, saturation: 1, brightness: 1),
            Color(hue: 0.33, saturation: 1, brightness: 1),
            Color(hue: 0.5, saturation: 1, brightness: 1),
            Color(hue: 0.66, saturation: 1, brightness: 1),
            Color(hue: 0.83, saturation: 1, brightness: 1),
            Color(hue: 1.0, saturation: 1, brightness: 1)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let indicatorX = selection.hue * width

            ZStack {
                Capsule(style: .continuous)
                    .fill(sliderGradient)
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)

                Circle()
                    .fill(Color(hue: selection.hue, saturation: 1, brightness: 1))
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.96), lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .position(x: min(max(indicatorX, 9), width - 9), y: geometry.size.height / 2)
            }
            .contentShape(Capsule(style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, 0), width)
                        selection.hue = x / width
                    }
            )
        }
    }
}

private extension StudioCustomColorSelection {
    var swiftUIColor: Color {
        switch canvasBackground {
        case let .solidColor(r, g, b, a):
            return Color(red: r, green: g, blue: b, opacity: a)
        case .linearGradient, .image:
            return .clear
        }
    }
}

// MARK: - PlatformExportRow（带画布切换）

private struct PlatformExportRow: View {
    let platform: PlatformKind
    let isSelected: Bool
    let isCurrentCanvas: Bool
    let exportResult: ExportedVariantResult?
    let onToggle: () -> Void
    let onSelectCanvas: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 平台比例图标（点击切换画布）— 按平台真实宽高比显示
            Button(action: onSelectCanvas) {
                let ar = platform.aspectRatio  // W/H
                // 容器固定 34×34，按比例缩放内部矩形
                let boxMaxW: CGFloat = 28
                let boxMaxH: CGFloat = 28
                let boxW: CGFloat = ar >= 1 ? boxMaxW : boxMaxH * ar
                let boxH: CGFloat = ar >= 1 ? boxMaxW / ar : boxMaxH
                ZStack {
                    // 外框（平台比例）
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isCurrentCanvas ? Color.black : Color.black.opacity(0.10))
                        .frame(width: boxW, height: boxH)
                    // 内部十字线（模拟屏幕内容）
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isCurrentCanvas ? Color.white.opacity(0.85) : Color.black.opacity(0.18))
                        .frame(width: boxW - 4, height: boxH - 4)
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(platform.title)
                    .font(.system(size: 13, weight: isCurrentCanvas ? .semibold : .regular))
                Text(platform.ratioLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 导出开关
            Button(action: onToggle) {
                if exportResult != nil {
                    Circle()
                        .fill(Color.white.opacity(0.42))
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle().stroke(Color.white.opacity(0.7), lineWidth: 1)
                        }
                        .overlay {
                            Circle().fill(Color.black.opacity(0.78)).frame(width: 7, height: 7)
                        }
                } else {
                    Circle()
                        .stroke(isSelected ? Color.black : Color.black.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().fill(isSelected ? Color.black : Color.clear).frame(width: 8, height: 8))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isCurrentCanvas ? Color.white.opacity(0.24) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

}

// MARK: - Export Status Card

private struct ExportStatusSummaryCard: View {
    let model: ExportStatusCardModel
    let onOpenItem: (ExportStatusCardItem) -> Void

    private var accentColor: Color {
        switch model.tone {
        case .success:
            return Color.black.opacity(0.72)
        case .info:
            return Color.black.opacity(0.72)
        case .error:
            return Color(red: 0.86, green: 0.28, blue: 0.22)
        }
    }

    private var tintBackground: Color {
        model.tone == .error ? accentColor.opacity(0.1) : Color.white.opacity(0.26)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(model.message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !model.items.isEmpty {
                VStack(spacing: 8) {
                    ForEach(model.items, id: \.fileURL) { item in
                        Button {
                            onOpenItem(item)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.subtitle)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.48))
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(accentColor)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.34))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Color.white.opacity(0.56), lineWidth: 0.8)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(tintBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Studio Background Preset Preview

private extension StudioBackgroundPreset {
    var previewSwatch: some View {
        switch background {
        case let .solidColor(r, g, b, a):
            return AnyView(Color(red: r, green: g, blue: b, opacity: a))
        case let .linearGradient(r1, g1, b1, r2, g2, b2, _):
            let points = background.gradientPointsForSwiftUI()
            return AnyView(
                LinearGradient(
                    colors: [Color(red: r1, green: g1, blue: b1), Color(red: r2, green: g2, blue: b2)],
                    startPoint: UnitPoint(points?.start ?? CGPoint(x: 0, y: 0)),
                    endPoint: UnitPoint(points?.end ?? CGPoint(x: 1, y: 1))
                )
            )
        case .image:
            return AnyView(Color.gray)
        }
    }
}

// MARK: - CameraShape 图标

private extension CameraShape {
    var iconLabel: String {
        switch self {
        case .circle:      return "⬤"
        case .roundedCard: return "▣"
        case .square:      return "■"
        case .rectangle:   return "▬"
        }
    }
}


private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - SharedPlayerView（接受外部传入的 AVPlayer）

private enum PlaybackPrimaryAction {
    case togglePlayback
    case restartFromBeginning
}

@MainActor
private func playbackPrimaryAction(for viewModel: AppViewModel) -> PlaybackPrimaryAction {
    if viewModel.playbackState == .paused,
       shouldRestartPlaybackFromBeginning(
        currentTime: viewModel.playbackPositionSeconds,
        duration: viewModel.playbackDurationSeconds
       ) {
        return .restartFromBeginning
    }
    return .togglePlayback
}

@MainActor
func playbackPrimaryButtonSymbol(for viewModel: AppViewModel) -> String {
    if viewModel.playbackState == .playing {
        return "pause.fill"
    }
    if playbackPrimaryAction(for: viewModel) == .restartFromBeginning {
        return "arrow.clockwise"
    }
    return "play.fill"
}

private struct SharedPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let playbackState: PlaybackState
    /// 裁剪出点（秒），播放到此处自动暂停；nil = 不限制
    var trimEndSeconds: Double? = nil
    let onPositionChange: (Double) -> Void
    let onSmoothPositionChange: (Double) -> Void
    let onPlaybackFinished: () -> Void

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill  // 填满容器，不留黑边
        view.player = player
        context.coordinator.startObserving(
            player: player,
            trimEndSeconds: trimEndSeconds,
            onPositionChange: onPositionChange,
            onSmoothPositionChange: onSmoothPositionChange,
            onPlaybackFinished: onPlaybackFinished
        )
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // player 或 trimEnd 变化时，重新挂载 observer
        let playerChanged = nsView.player !== player
        let trimChanged   = context.coordinator.currentTrimEnd != trimEndSeconds
        if playerChanged || trimChanged {
            if playerChanged { nsView.player = player }
            context.coordinator.startObserving(
                player: player,
                trimEndSeconds: trimEndSeconds,
                onPositionChange: onPositionChange,
                onSmoothPositionChange: onSmoothPositionChange,
                onPlaybackFinished: onPlaybackFinished
            )
        }
        switch playbackState {
        case .playing:
            if shouldRestartPlaybackFromBeginning(
                currentTime: player.currentTime().seconds,
                duration: player.currentItem?.duration.seconds ?? 0
            ) {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    player.play()
                }
            } else if player.rate == 0 {
                player.play()
            }
        case .paused:
            if player.rate != 0 { player.pause() }
        }
    }

    func makeCoordinator() -> VideoCoordinator { VideoCoordinator() }

    final class VideoCoordinator {
        private var timeObserver: Any?
        private var playbackEndObserver: NSObjectProtocol?
        private weak var player: AVPlayer?
        /// 上一次挂载时使用的 trimEnd，用于检测变化
        var currentTrimEnd: Double? = nil

        func startObserving(
            player: AVPlayer,
            trimEndSeconds: Double?,
            onPositionChange: @escaping (Double) -> Void,
            onSmoothPositionChange: @escaping (Double) -> Void,
            onPlaybackFinished: @escaping () -> Void
        ) {
            if let obs = timeObserver { self.player?.removeTimeObserver(obs) }
            if let playbackEndObserver {
                NotificationCenter.default.removeObserver(playbackEndObserver)
            }
            self.player = player
            self.currentTrimEnd = trimEndSeconds
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
                queue: .main
            ) { [weak player] time in
                let seconds = time.seconds
                // 若播放超过 trimEnd，自动暂停并通知上层
                if let end = trimEndSeconds, seconds >= end - 0.05 {
                    player?.pause()
                    onPlaybackFinished()
                    return
                }
                onPositionChange(seconds)
                onSmoothPositionChange(seconds)
            }
            playbackEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                onPlaybackFinished()
            }
        }

        deinit {
            if let obs = timeObserver { player?.removeTimeObserver(obs) }
            if let playbackEndObserver {
                NotificationCenter.default.removeObserver(playbackEndObserver)
            }
        }
    }
}

// MARK: - Video Player Surface（复用）

private struct VideoPlayerSurface: NSViewRepresentable {
    let url: URL
    let playbackState: PlaybackState
    let onPlaybackStateChange: (PlaybackState) -> Void
    let onPositionChange: (Double) -> Void

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        let player = AVPlayer(url: url)
        view.player = player
        context.coordinator.player = player
        context.coordinator.startObserving(player: player, onPositionChange: onPositionChange)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        guard let player = nsView.player else { return }
        if let currentURL = (player.currentItem?.asset as? AVURLAsset)?.url, currentURL != url {
            let newPlayer = AVPlayer(url: url)
            nsView.player = newPlayer
            context.coordinator.player = newPlayer
            context.coordinator.startObserving(player: newPlayer, onPositionChange: onPositionChange)
        }
        switch playbackState {
        case .playing:  if player.rate == 0 { player.play() }
        case .paused:   if player.rate != 0 { player.pause() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVPlayer?
        private var timeObserver: Any?

        func startObserving(player: AVPlayer, onPositionChange: @escaping (Double) -> Void) {
            if let old = timeObserver { self.player?.removeTimeObserver(old) }
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
                queue: .main
            ) { time in
                onPositionChange(time.seconds)
            }
        }

        deinit {
            if let obs = timeObserver { player?.removeTimeObserver(obs) }
        }
    }
}

// MARK: - ExportSelection Helper

private extension ExportSelection {
    func isEnabled(_ platform: PlatformKind) -> Bool {
        variants.first(where: { $0.platform == platform })?.exportEnabled ?? false
    }
}
