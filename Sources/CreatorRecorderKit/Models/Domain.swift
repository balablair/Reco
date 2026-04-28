import Foundation
import CoreGraphics

public enum PlatformKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case xiaohongshu
    case douyin
    case bilibili

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .xiaohongshu: return "Xiaohongshu"
        case .douyin: return "Douyin"
        case .bilibili: return "Bilibili"
        }
    }

    public var ratioLabel: String {
        switch self {
        case .xiaohongshu: return "3:4"
        case .douyin: return "9:16"
        case .bilibili: return "16:9"
        }
    }

    public var aspectRatio: CGFloat {
        switch self {
        case .xiaohongshu: return 3.0 / 4.0
        case .douyin: return 9.0 / 16.0
        case .bilibili: return 16.0 / 9.0
        }
    }

    public var exportRenderSize: CGSize {
        switch self {
        case .xiaohongshu: return CGSize(width: 1080, height: 1440)
        case .douyin: return CGSize(width: 1080, height: 1920)
        case .bilibili: return CGSize(width: 1920, height: 1080)
        }
    }
}

public enum AspectRatioPreset: String, Codable, Sendable {
    case portraitCard
    case portraitStory
    case landscapeWide
}

public enum SafeAreaPreset: String, Codable, Sendable {
    case xiaohongshu
    case douyin
    case bilibili
}

public enum CameraShape: String, Codable, CaseIterable, Sendable {
case circle
case roundedCard
case square
case rectangle   // 横版 16:9

public var usesSquarePixels: Bool {
switch self {
case .circle, .roundedCard, .square:
    return true
case .rectangle:
    return false
}
}

/// 该形状对应的宽高比（width / height），nil = 1:1
public var aspectRatio: CGFloat? {
switch self {
case .circle, .roundedCard, .square: return nil   // 1:1
case .rectangle: return 16.0 / 9.0
}
}
}


public func pipCornerRadius(for shape: CameraShape, in size: CGSize) -> CGFloat {
    switch shape {
    case .circle:
        return min(size.width, size.height) / 2
    case .roundedCard:
        return 18
    case .square:
        return 6
    case .rectangle:
        return 12
    }
}

public func pipPreviewCornerRadius(for shape: CameraShape, frame: CanvasElementFrame, in canvasSize: CGSize) -> CGFloat {
    pipCornerRadius(for: shape, in: frame.toRect(in: canvasSize).size)
}

public func makePipClipPath(shape: CameraShape, rect: CGRect) -> CGPath? {
    guard rect.width > 0, rect.height > 0 else { return nil }

    switch shape {
    case .circle:
        return CGPath(ellipseIn: rect, transform: nil)
    case .roundedCard, .square, .rectangle:
        let radius = min(pipCornerRadius(for: shape, in: rect.size), min(rect.width, rect.height) / 2)
        return CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }
}

public struct CameraStyle: Codable, Equatable, Sendable {
    public var shape: CameraShape
    public var shadow: Double
    public var borderOpacity: Double
    public var blurEnabled: Bool

    public init(shape: CameraShape, shadow: Double, borderOpacity: Double, blurEnabled: Bool) {
        self.shape = shape
        self.shadow = shadow
        self.borderOpacity = borderOpacity
        self.blurEnabled = blurEnabled
    }

    public static let creatorDefault = CameraStyle(
        shape: .roundedCard,
        shadow: 0.18,
        borderOpacity: 0.22,
        blurEnabled: true
    )
}

/// 摄像头美颜 & 灯光设置
public struct CameraBeautySettings: Codable, Equatable, Sendable {
    /// 磨皮强度 0~1（0=关闭）
    public var smoothing: Double
    /// 亮度 -0.5~0.5（0=原始）
    public var brightness: Double
    /// 对比度 0.5~1.5（1=原始）
    public var contrast: Double
    /// 色温偏移：正=暖，负=冷，-2000~2000（0=原始）
    public var warmth: Double
    /// 曝光补偿（补光）-1~1（0=原始）
    public var exposure: Double

    public init(
        smoothing: Double = 0.0,
        brightness: Double = 0.0,
        contrast: Double = 1.0,
        warmth: Double = 0.0,
        exposure: Double = 0.0
    ) {
        self.smoothing = smoothing
        self.brightness = brightness
        self.contrast = contrast
        self.warmth = warmth
        self.exposure = exposure
    }

    public static let `default` = CameraBeautySettings()

    /// 是否所有参数都是默认值（无需处理）
    public var isDefault: Bool {
        smoothing == 0 && brightness == 0 && contrast == 1.0 && warmth == 0 && exposure == 0
    }
}

public struct CaptureRegion: Equatable, Codable, Sendable {
    public var origin: CGPoint
    public var size: CGSize

    public init(origin: CGPoint, size: CGSize) {
        self.origin = origin
        self.size = size
    }

    public init(from start: CGPoint, to end: CGPoint, minimumSize: CGSize = .init(width: 160, height: 120)) {
        let origin = CGPoint(x: min(start.x, end.x), y: min(start.y, end.y))
        let size = CGSize(
            width: max(abs(end.x - start.x), minimumSize.width),
            height: max(abs(end.y - start.y), minimumSize.height)
        )

        self.init(origin: origin, size: size)
    }

    public static let defaultSelection = CaptureRegion(
        origin: .init(x: 188, y: 120),
        size: .init(width: 560, height: 360)
    )

    public var maxX: CGFloat { origin.x + size.width }
    public var maxY: CGFloat { origin.y + size.height }
    public var rect: CGRect { CGRect(origin: origin, size: size) }

    public func clamped(to canvas: CGSize) -> CaptureRegion {
        let clampedSize = CGSize(
            width: min(size.width, canvas.width),
            height: min(size.height, canvas.height)
        )
        let clampedOrigin = CGPoint(
            x: min(max(origin.x, 0), max(canvas.width - clampedSize.width, 0)),
            y: min(max(origin.y, 0), max(canvas.height - clampedSize.height, 0))
        )

        return CaptureRegion(origin: clampedOrigin, size: clampedSize)
    }
}

public struct CameraOverlayLayout: Equatable, Codable, Sendable {
    public static let minimumSize: CGFloat = 72
    public static let inset: CGFloat = 18

    public var origin: CGPoint
    public var size: CGSize
    public var style: CameraStyle

    public init(origin: CGPoint, size: CGSize, style: CameraStyle) {
        self.origin = origin
        self.size = size
        self.style = style
    }

    public static func `default`(in region: CaptureRegion) -> CameraOverlayLayout {
        let width = min(max(region.size.width * 0.22, 96), 148)
        let size = CGSize(width: width, height: width)
        let origin = CGPoint(
            x: max(region.origin.x + region.size.width - size.width - Self.inset, region.origin.x),
            y: max(region.origin.y + region.size.height - size.height - Self.inset, region.origin.y)
        )

        return CameraOverlayLayout(origin: origin, size: size, style: .creatorDefault)
    }

    public var rect: CGRect { CGRect(origin: origin, size: size) }

    public func clamped(to region: CaptureRegion, inset: CGFloat = CameraOverlayLayout.inset) -> CameraOverlayLayout {
        // 保持当前宽高比进行 clamp（矩形形状宽高可以不同）
        let shape = style.shape
        let clampedSize: CGSize
        if let ar = shape.aspectRatio {
            // 矩形：以高度为基准 clamp
            let maxH = max(region.size.height - inset, Self.minimumSize)
            let minH: CGFloat = Self.minimumSize
            let h = min(max(size.height, minH), maxH)
            let w = min(h * ar, region.size.width - inset)
            clampedSize = CGSize(width: max(w, Self.minimumSize), height: h)
        } else {
            let maxDimension = max(min(region.size.width - inset, region.size.height - inset), Self.minimumSize)
            let side = min(max(size.width, Self.minimumSize), maxDimension)
            clampedSize = CGSize(width: side, height: side)
        }
        let minX = region.origin.x
        let minY = region.origin.y
        let maxX = region.maxX - clampedSize.width - inset
        let maxY = region.maxY - clampedSize.height - inset

        let clampedOrigin = CGPoint(
            x: min(max(origin.x, minX), max(maxX, minX)),
            y: min(max(origin.y, minY), max(maxY, minY))
        )

        return CameraOverlayLayout(origin: clampedOrigin, size: clampedSize, style: style)
    }

    public func resized(by delta: CGSize, in region: CaptureRegion) -> CameraOverlayLayout {
        let availableWidth = max(region.maxX - origin.x - Self.inset, Self.minimumSize)
        let availableHeight = max(region.maxY - origin.y - Self.inset, Self.minimumSize)
        let maxDimension = max(min(availableWidth, availableHeight), Self.minimumSize)
        let nextSide = min(max(size.width + max(delta.width, delta.height), Self.minimumSize), maxDimension)
        return CameraOverlayLayout(origin: origin, size: CGSize(width: nextSide, height: nextSide), style: style)
    }

    /// 切换形状时同时调整 size 以匹配新形状的宽高比（基准边为较小边）
    public func withShape(_ shape: CameraShape) -> CameraOverlayLayout {
        var copy = self
        copy.style.shape = shape
        // 根据形状的宽高比重新计算 size
        let base = min(size.width, size.height)
        if let ar = shape.aspectRatio {
            copy.size = CGSize(width: base * ar, height: base)
        } else {
            copy.size = CGSize(width: base, height: base)
        }
        return copy
    }
}

public enum ProjectTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case xiaohongshu
    case douyin
    case bilibili

    public var id: String { rawValue }

    public var platform: PlatformKind {
        switch self {
        case .xiaohongshu: return .xiaohongshu
        case .douyin: return .douyin
        case .bilibili: return .bilibili
        }
    }

    public var aspectRatio: AspectRatioPreset {
        switch self {
        case .xiaohongshu: return .portraitStory
        case .douyin: return .portraitStory
        case .bilibili: return .landscapeWide
        }
    }

    public var safeAreaPreset: SafeAreaPreset {
        switch self {
        case .xiaohongshu: return .xiaohongshu
        case .douyin: return .douyin
        case .bilibili: return .bilibili
        }
    }

    public var cameraStyle: CameraStyle {
        .creatorDefault
    }
}

public struct PlatformVariant: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var platform: PlatformKind
    public var aspectRatio: AspectRatioPreset
    public var safeAreaPreset: SafeAreaPreset
    public var cameraStyle: CameraStyle
    public var exportEnabled: Bool

    public init(
        id: UUID = UUID(),
        platform: PlatformKind,
        aspectRatio: AspectRatioPreset,
        safeAreaPreset: SafeAreaPreset,
        cameraStyle: CameraStyle,
        exportEnabled: Bool = true
    ) {
        self.id = id
        self.platform = platform
        self.aspectRatio = aspectRatio
        self.safeAreaPreset = safeAreaPreset
        self.cameraStyle = cameraStyle
        self.exportEnabled = exportEnabled
    }

    public init(template: ProjectTemplate) {
        self.init(
            platform: template.platform,
            aspectRatio: template.aspectRatio,
            safeAreaPreset: template.safeAreaPreset,
            cameraStyle: template.cameraStyle,
            exportEnabled: true
        )
    }
}

public struct RecordingProject: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var variants: [PlatformVariant]

    public init(id: UUID = UUID(), name: String, variants: [PlatformVariant]) {
        self.id = id
        self.name = name
        self.variants = variants
    }

    public static func newProject(name: String) -> RecordingProject {
        RecordingProject(
            name: name,
            variants: [
                PlatformVariant(template: .xiaohongshu),
                PlatformVariant(template: .douyin),
                PlatformVariant(template: .bilibili),
            ]
        )
    }
}

public enum AppPhase: Equatable {
    case preparation
    case recording
    case completion
    case editing
}

/// Studio 预览音频来源优先级
public enum StudioPreviewAudioSource: Equatable, Sendable {
    case camera   // 有摄像头音频时优先使用
    case screen   // 无摄像头音频时使用屏幕音频
    case none     // 两者都没有
}

/// 决定 Studio 预览时的首选音频来源
/// 规则：有摄像头音频时优先跟随摄像头（避免双声道叠加）
public func preferredStudioPreviewAudioSource(
    hasScreenAudio: Bool,
    hasCameraAudio: Bool
) -> StudioPreviewAudioSource {
    if hasCameraAudio { return .camera }
    if hasScreenAudio { return .screen }
    return .none
}

public enum RecordingState: Equatable, Sendable {
    case idle
    case recording
    case failed(String)
}

public struct SmartAutoZoomClickEvent: Equatable, Codable, Sendable {
    public var timestampSeconds: Double
    public var normalizedX: Double
    public var normalizedY: Double

    public init(timestampSeconds: Double, normalizedX: Double, normalizedY: Double) {
        self.timestampSeconds = max(timestampSeconds, 0)
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
    }
}

public struct SmartAutoZoomSettings: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var zoomScale: Double
    public var leadInSeconds: Double
    public var holdSeconds: Double
    public var releaseSeconds: Double
    public var mergeGapSeconds: Double

    public init(
        isEnabled: Bool = false,
        zoomScale: Double = 2,
        leadInSeconds: Double = 0.2,
        holdSeconds: Double = 0.6,
        releaseSeconds: Double = 0.3,
        mergeGapSeconds: Double = 0.15
    ) {
        self.isEnabled = isEnabled
        self.zoomScale = zoomScale
        self.leadInSeconds = leadInSeconds
        self.holdSeconds = holdSeconds
        self.releaseSeconds = releaseSeconds
        self.mergeGapSeconds = mergeGapSeconds
    }

    public var sanitizedZoomScale: Double {
        max(zoomScale, 1)
    }
}

public struct SmartAutoZoomSegment: Equatable, Codable, Sendable {
    public var startSeconds: Double
    public var focusSeconds: Double
    public var holdEndSeconds: Double
    public var endSeconds: Double
    public var normalizedX: Double
    public var normalizedY: Double
    public var zoomScale: Double

    public init(
        startSeconds: Double,
        focusSeconds: Double,
        holdEndSeconds: Double,
        endSeconds: Double,
        normalizedX: Double,
        normalizedY: Double,
        zoomScale: Double
    ) {
        self.startSeconds = startSeconds
        self.focusSeconds = focusSeconds
        self.holdEndSeconds = holdEndSeconds
        self.endSeconds = endSeconds
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.zoomScale = zoomScale
    }
}

public struct RecordingResult: Equatable, Codable, Sendable {
    public var fileURL: URL
    public var durationSeconds: Double
    public var fileSizeBytes: Int64
    /// 摄像头独立录像文件（分开录制时才有值）
    public var cameraFileURL: URL?
    /// 录制期间采集到的点击事件，供 smart auto-zoom 回放使用。
    public var cursorClickEvents: [SmartAutoZoomClickEvent]

    public init(
        fileURL: URL,
        durationSeconds: Double,
        fileSizeBytes: Int64,
        cameraFileURL: URL? = nil,
        cursorClickEvents: [SmartAutoZoomClickEvent] = []
    ) {
        self.fileURL = fileURL
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.cameraFileURL = cameraFileURL
        self.cursorClickEvents = cursorClickEvents
    }

    public var isPreviewAvailable: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public var hasCameraRecording: Bool {
        guard let url = cameraFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

public struct DisplaySource: Identifiable, Equatable, Codable, Sendable {
    public var id: UInt32
    public var name: String
    public var frame: CGRect
    public var isPrimary: Bool
    public var pointPixelScale: CGFloat

    public init(id: UInt32, name: String, frame: CGRect, isPrimary: Bool, pointPixelScale: CGFloat = 1) {
        self.id = id
        self.name = name
        self.frame = frame
        self.isPrimary = isPrimary
        self.pointPixelScale = pointPixelScale
    }

    public static let placeholder = DisplaySource(
        id: 1,
        name: "Main Display",
        frame: .init(x: 0, y: 0, width: 1728, height: 1117),
        isPrimary: true,
        pointPixelScale: 1
    )
}

/// 可录制的窗口信息
public struct WindowSource: Identifiable, Equatable, Sendable {
    public var id: UInt32       // CGWindowID
    public var appName: String
    public var windowTitle: String
    public var frame: CGRect    // 屏幕坐标（AppKit，左下原点）
    public var appBundleID: String

    public init(id: UInt32, appName: String, windowTitle: String, frame: CGRect, appBundleID: String) {
        self.id = id
        self.appName = appName
        self.windowTitle = windowTitle
        self.frame = frame
        self.appBundleID = appBundleID
    }

    public var displayName: String {
        windowTitle.isEmpty ? appName : "\(appName) · \(windowTitle)"
    }
}

/// 捕获源类型
public enum CaptureSource: Equatable, Sendable {
    case screenRegion                       // 用户手动框选区域
    case window(WindowSource)               // 特定窗口
}

public enum StudioWindowVisibilityAction: Equatable, Sendable {
    case none
    case hide
    case show
}

public struct DesktopRegionPickerConfiguration: Equatable, Sendable {
    public var activatesApp: Bool
    public var canBecomeKey: Bool
    public var cancelsOnEscape: Bool

    public init(activatesApp: Bool, canBecomeKey: Bool, cancelsOnEscape: Bool) {
        self.activatesApp = activatesApp
        self.canBecomeKey = canBecomeKey
        self.cancelsOnEscape = cancelsOnEscape
    }

    public static let interactiveOverlay = DesktopRegionPickerConfiguration(
        activatesApp: true,
        canBecomeKey: true,
        cancelsOnEscape: true
    )
}

public enum DesktopRegionPickerSessionAction: Equatable, Sendable {
    case none
    case cancel
}

public struct DesktopRegionPickerSession: Equatable, Sendable {
    private var isActive = false

    public init() {}

    @discardableResult
    public mutating func begin() -> Bool {
        let shouldBegin = !isActive
        isActive = true
        return shouldBegin
    }

    public mutating func finish() {
        isActive = false
    }

    public mutating func overlayDidResignActive() -> DesktopRegionPickerSessionAction {
        guard isActive else { return .none }
        isActive = false
        return .cancel
    }
}

public struct StudioWindowVisibilityState: Equatable, Sendable {
    private var shouldRestoreAfterRecording = false

    public init() {}

    public mutating func recordingDidStart(studioIsVisible: Bool) -> StudioWindowVisibilityAction {
        shouldRestoreAfterRecording = studioIsVisible
        return studioIsVisible ? .hide : .none
    }

    public mutating func recordingDidEnd() -> StudioWindowVisibilityAction {
        defer { shouldRestoreAfterRecording = false }
        return shouldRestoreAfterRecording ? .show : .none
    }
}

public enum FloatingPanelPlacement {
    public static func restoredOrigin(storedOrigin: CGPoint, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let sanitizedVisibleFrame = sanitize(visibleFrame: visibleFrame)
        return clamp(origin: storedOrigin, panelSize: panelSize, visibleFrame: sanitizedVisibleFrame)
    }

    public static func snappedOrigin(
        proposedOrigin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        snapDistance: CGFloat = 18
    ) -> CGPoint {
        let sanitizedVisibleFrame = sanitize(visibleFrame: visibleFrame)
        let clamped = clamp(origin: proposedOrigin, panelSize: panelSize, visibleFrame: sanitizedVisibleFrame)
        let maxX = sanitizedVisibleFrame.maxX - panelSize.width
        let maxY = sanitizedVisibleFrame.maxY - panelSize.height

        return CGPoint(
            x: snap(value: clamped.x, min: sanitizedVisibleFrame.minX, max: maxX, threshold: snapDistance),
            y: snap(value: clamped.y, min: sanitizedVisibleFrame.minY, max: maxY, threshold: snapDistance)
        )
    }

    private static func sanitize(visibleFrame: CGRect) -> CGRect {
        guard
            visibleFrame.minX.isFinite,
            visibleFrame.minY.isFinite,
            visibleFrame.width.isFinite,
            visibleFrame.height.isFinite,
            visibleFrame.width > 0,
            visibleFrame.height > 0
        else {
            return .zero
        }

        return visibleFrame
    }

    private static func clamp(origin: CGPoint, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        guard
            origin.x.isFinite,
            origin.y.isFinite,
            panelSize.width.isFinite,
            panelSize.height.isFinite,
            visibleFrame.minX.isFinite,
            visibleFrame.minY.isFinite,
            visibleFrame.maxX.isFinite,
            visibleFrame.maxY.isFinite
        else {
            return CGPoint(x: visibleFrame.minX, y: visibleFrame.minY)
        }

        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX), max(visibleFrame.maxX - panelSize.width, visibleFrame.minX)),
            y: min(max(origin.y, visibleFrame.minY), max(visibleFrame.maxY - panelSize.height, visibleFrame.minY))
        )
    }

    private static func snap(value: CGFloat, min: CGFloat, max: CGFloat, threshold: CGFloat) -> CGFloat {
        if abs(value - min) <= threshold {
            return min
        }
        if abs(value - max) <= threshold {
            return max
        }
        return value
    }
}

public func makeRecordedCursorClick(
    timestampSeconds: Double,
    screenLocation: CGPoint,
    configuration: CaptureSessionConfiguration
) -> SmartAutoZoomClickEvent? {
    let sourceFrame = configuration.captureSourceFrameInScreenCoordinates
    guard sourceFrame.width > 0, sourceFrame.height > 0, sourceFrame.contains(screenLocation) else {
        return nil
    }

    let normalizedX = ((screenLocation.x - sourceFrame.minX) / sourceFrame.width).clamped(to: 0...1)
    let normalizedY = ((sourceFrame.maxY - screenLocation.y) / sourceFrame.height).clamped(to: 0...1)
    return SmartAutoZoomClickEvent(
        timestampSeconds: max(timestampSeconds, 0),
        normalizedX: normalizedX,
        normalizedY: normalizedY
    )
}

public struct CaptureSessionConfiguration: Equatable, Sendable {
    public var display: DisplaySource
    public var region: CaptureRegion
    public var canvasSize: CGSize
    public var cameraOverlay: CameraOverlayLayout?
    public var microphoneEnabled: Bool
    public var systemAudioEnabled: Bool
    /// 非 nil 时按指定窗口进行捕获（忽略 region/display 过滤）
    public var windowSource: WindowSource?

    public init(
        display: DisplaySource,
        region: CaptureRegion,
        canvasSize: CGSize,
        cameraOverlay: CameraOverlayLayout?,
        microphoneEnabled: Bool,
        systemAudioEnabled: Bool,
        windowSource: WindowSource? = nil
    ) {
        self.display = display
        self.region = region
        self.canvasSize = canvasSize
        self.cameraOverlay = cameraOverlay
        self.microphoneEnabled = microphoneEnabled
        self.systemAudioEnabled = systemAudioEnabled
        self.windowSource = windowSource
    }

    public static func fromScreenSelection(
        _ selectionRect: CGRect,
        on display: DisplaySource,
        cameraOverlay: CameraOverlayLayout?,
        microphoneEnabled: Bool,
        systemAudioEnabled: Bool
    ) -> CaptureSessionConfiguration {
        let clippedRect = selectionRect.intersection(display.frame).integral
        let localRect = clippedRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        return CaptureSessionConfiguration(
            display: display,
            region: CaptureRegion(origin: localRect.origin, size: localRect.size),
            canvasSize: display.frame.size,
            cameraOverlay: cameraOverlay,
            microphoneEnabled: microphoneEnabled,
            systemAudioEnabled: systemAudioEnabled
        )
    }

    public static func fromWindow(
        _ window: WindowSource,
        on display: DisplaySource,
        cameraOverlay: CameraOverlayLayout?,
        microphoneEnabled: Bool,
        systemAudioEnabled: Bool
    ) -> CaptureSessionConfiguration {
        // 以窗口实际 frame 作为 region
        let region = CaptureRegion(origin: window.frame.origin, size: window.frame.size)
        return CaptureSessionConfiguration(
            display: display,
            region: region,
            canvasSize: window.frame.size,
            cameraOverlay: cameraOverlay,
            microphoneEnabled: microphoneEnabled,
            systemAudioEnabled: systemAudioEnabled,
            windowSource: window
        )
    }

    public var normalizedRegion: CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        return CGRect(
            x: max(0, min(region.origin.x / canvasSize.width, 1)),
            y: max(0, min(region.origin.y / canvasSize.height, 1)),
            width: max(0.05, min(region.size.width / canvasSize.width, 1)),
            height: max(0.05, min(region.size.height / canvasSize.height, 1))
        )
    }

    public func sourceRect(in displayFrame: CGRect) -> CGRect {
        let unitRect = normalizedRegion
        return CGRect(
            x: displayFrame.minX + displayFrame.width * unitRect.origin.x,
            y: displayFrame.minY + displayFrame.height * unitRect.origin.y,
            width: displayFrame.width * unitRect.size.width,
            height: displayFrame.height * unitRect.size.height
        ).integral
    }

    public var displaySourceRect: CGRect {
        sourceRect(in: display.frame)
    }

    public var displayLocalSourceRect: CGRect {
        displaySourceRect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }

    public var captureSourceFrameInScreenCoordinates: CGRect {
        if let windowSource {
            return windowSource.frame.integral
        }
        return displaySourceRect
    }
}

struct ScreenStreamDescriptor: Equatable, Sendable {
    let displayID: UInt32
    let sourceRect: CGRect
    let outputSize: CGSize
    let capturesAudio: Bool
    let captureMicrophone: Bool
    let showsCursor: Bool
    let queueDepth: Int

    init(configuration: CaptureSessionConfiguration, pointPixelScale: CGFloat? = nil) {
        let scale = max(pointPixelScale ?? configuration.display.pointPixelScale, 1)
        let localSourceRect = configuration.displayLocalSourceRect

        self.displayID = configuration.display.id
        self.sourceRect = localSourceRect
        self.outputSize = CGSize(
            width: max(localSourceRect.width * scale, 1),
            height: max(localSourceRect.height * scale, 1)
        )
        self.capturesAudio = configuration.systemAudioEnabled
        self.captureMicrophone = configuration.microphoneEnabled
        self.showsCursor = true
        self.queueDepth = 5
    }
}

public struct ExportedVariantResult: Equatable, Codable, Sendable {
    public var platform: PlatformKind
    public var fileURL: URL
    public var renderSize: CGSize
    public var fileSizeBytes: Int64

    public init(platform: PlatformKind, fileURL: URL, renderSize: CGSize, fileSizeBytes: Int64) {
        self.platform = platform
        self.fileURL = fileURL
        self.renderSize = renderSize
        self.fileSizeBytes = fileSizeBytes
    }
}

public enum SourceAssetKind: String, Equatable, Codable, Sendable {
    case screen
    case camera

    public var title: String {
        switch self {
        case .screen: return "Screen"
        case .camera: return "Camera"
        }
    }
}

public struct ExportedSourceAsset: Equatable, Codable, Sendable {
    public var kind: SourceAssetKind
    public var fileURL: URL
    public var fileSizeBytes: Int64

    public init(kind: SourceAssetKind, fileURL: URL, fileSizeBytes: Int64) {
        self.kind = kind
        self.fileURL = fileURL
        self.fileSizeBytes = fileSizeBytes
    }
}

public struct ExportedVideoMetadata: Equatable, Sendable {
    public var renderSize: CGSize
    public var durationSeconds: Double

    public init(renderSize: CGSize, durationSeconds: Double) {
        self.renderSize = renderSize
        self.durationSeconds = durationSeconds
    }
}

public enum PlatformExportValidationError: Equatable, LocalizedError, Sendable {
    case invalidRenderSize(expected: CGSize, actual: CGSize)
    case invalidDuration(expectedMinimum: Double, actual: Double)

    public var errorDescription: String? {
        switch self {
        case let .invalidRenderSize(expected, actual):
            return "Exported video size mismatch. Expected \(Int(expected.width))x\(Int(expected.height)), got \(Int(actual.width))x\(Int(actual.height))."
        case let .invalidDuration(expectedMinimum, actual):
            return "Exported video duration is too short. Expected at least \(expectedMinimum)s, got \(actual)s."
        }
    }
}

public enum PlatformExportValidator {
    public static func validate(
        metadata: ExportedVideoMetadata,
        for platform: PlatformKind,
        sourceDurationSeconds: Double
    ) -> PlatformExportValidationError? {
        let expectedSize = platform.exportRenderSize
        if metadata.renderSize != expectedSize {
            return .invalidRenderSize(expected: expectedSize, actual: metadata.renderSize)
        }

        let expectedMinimumDuration = max((sourceDurationSeconds * 0.95 * 10).rounded() / 10, 0)
        if metadata.durationSeconds < expectedMinimumDuration {
            return .invalidDuration(expectedMinimum: expectedMinimumDuration, actual: metadata.durationSeconds)
        }

        return nil
    }
}

public enum ExportState: Equatable, Sendable {
    case idle
    case exporting
    case completed([ExportedVariantResult])
    case failed(String)
}

public enum SourceExportState: Equatable, Sendable {
case idle
case exporting
case completed([ExportedSourceAsset])
case failed(String)
}

public enum ExportStatusCardTone: Equatable, Sendable {
case success
case info
case error
}

public struct ExportStatusCardItem: Equatable, Sendable {
public var title: String
public var subtitle: String
public var fileURL: URL

public init(title: String, subtitle: String, fileURL: URL) {
self.title = title
self.subtitle = subtitle
self.fileURL = fileURL
}
}

public struct ExportStatusCardModel: Equatable, Sendable {
public var tone: ExportStatusCardTone
public var title: String
public var message: String
public var symbolName: String
public var items: [ExportStatusCardItem]

public init(
    tone: ExportStatusCardTone,
    title: String,
    message: String,
    symbolName: String,
    items: [ExportStatusCardItem]
) {
    self.tone = tone
    self.title = title
    self.message = message
    self.symbolName = symbolName
    self.items = items
}
}

public struct RecordingCompletionCardModel: Equatable, Sendable {
public var eyebrow: String
public var title: String
public var statusPillTitle: String
public var durationLabel: String
public var exportSourceButtonTitle: String
public var exportSourceButtonEnabled: Bool
public var primaryActionTitle: String

public init(
    eyebrow: String,
    title: String,
    statusPillTitle: String,
    durationLabel: String,
    exportSourceButtonTitle: String,
    exportSourceButtonEnabled: Bool,
    primaryActionTitle: String
) {
    self.eyebrow = eyebrow
    self.title = title
    self.statusPillTitle = statusPillTitle
    self.durationLabel = durationLabel
    self.exportSourceButtonTitle = exportSourceButtonTitle
    self.exportSourceButtonEnabled = exportSourceButtonEnabled
    self.primaryActionTitle = primaryActionTitle
}
}

public struct ExportToastModel: Equatable, Sendable {
public var message: String
public var actionTitle: String
public var targetURL: URL

public init(message: String, actionTitle: String, targetURL: URL) {
    self.message = message
    self.actionTitle = actionTitle
    self.targetURL = targetURL
}
}

public func makeRecordingCompletionCardModel(
    recordingElapsedSeconds: Int,
    sourceExportState: SourceExportState
) -> RecordingCompletionCardModel {
    let totalSeconds = max(recordingElapsedSeconds, 0)
    let minutes = totalSeconds / 60
    let remainingSeconds = totalSeconds % 60
    let durationLabel = String(format: "%02d:%02d", minutes, remainingSeconds)

    let exportSourceButtonTitle: String
    let exportSourceButtonEnabled: Bool
    switch sourceExportState {
    case .exporting:
        exportSourceButtonTitle = "导出中..."
        exportSourceButtonEnabled = false
    case .completed:
        exportSourceButtonTitle = "已导出原素材"
        exportSourceButtonEnabled = true
    case .idle, .failed:
        exportSourceButtonTitle = "导出原素材"
        exportSourceButtonEnabled = true
    }

    return RecordingCompletionCardModel(
        eyebrow: "Recording Finished",
        title: "录制完成",
        statusPillTitle: "素材已保存",
        durationLabel: durationLabel,
        exportSourceButtonTitle: exportSourceButtonTitle,
        exportSourceButtonEnabled: exportSourceButtonEnabled,
        primaryActionTitle: "打开 Studio"
    )
}

public func makeVariantExportStatusCardModel(_ state: ExportState) -> ExportStatusCardModel? {
switch state {
case let .completed(results):
    let count = results.count
    let title = count > 0 ? "已导出 \(count) 个平台" : "导出完成"
    let items = results.map {
        ExportStatusCardItem(
            title: $0.platform.title,
            subtitle: ByteCountFormatter.string(fromByteCount: $0.fileSizeBytes, countStyle: .file),
            fileURL: $0.fileURL
        )
    }
    return ExportStatusCardModel(
        tone: .success,
        title: title,
        message: "",
        symbolName: "checkmark.seal.fill",
        items: items
    )
case let .failed(message):
    return ExportStatusCardModel(
        tone: .error,
        title: "导出失败",
        message: message,
        symbolName: "exclamationmark.triangle.fill",
        items: []
    )
case .idle, .exporting:
    return nil
}
}

public func makeSourceExportStatusCardModel(_ state: SourceExportState) -> ExportStatusCardModel? {
switch state {
case let .completed(results):
    let items = results.map {
        ExportStatusCardItem(
            title: $0.kind.title,
            subtitle: ByteCountFormatter.string(fromByteCount: $0.fileSizeBytes, countStyle: .file),
            fileURL: $0.fileURL
        )
    }
    return ExportStatusCardModel(
        tone: .info,
        title: "原素材已就绪",
        message: "可继续在其他剪辑软件中精修",
        symbolName: "shippingbox.fill",
        items: items
    )
case let .failed(message):
    return ExportStatusCardModel(
        tone: .error,
        title: "原素材导出失败",
        message: message,
        symbolName: "exclamationmark.triangle.fill",
        items: []
    )
case .idle, .exporting:
    return nil
}
}

public func makeVariantExportToastModel(_ state: ExportState) -> ExportToastModel? {
switch state {
case let .completed(results):
    guard let first = results.first else { return nil }
    return ExportToastModel(
        message: "已导出 \(results.count) 个平台",
        actionTitle: "查看",
        targetURL: first.fileURL
    )
case .idle, .exporting, .failed:
    return nil
}
}

public func makeSourceExportToastModel(_ state: SourceExportState) -> ExportToastModel? {
switch state {
case let .completed(results):
    guard let first = results.first else { return nil }
    return ExportToastModel(
        message: "原素材已导出",
        actionTitle: "查看",
        targetURL: first.fileURL
    )
case .idle, .exporting, .failed:
    return nil
}
}

public enum PlaybackState: Equatable, Sendable {
case paused
case playing
}


public struct PlatformPreviewCrop: Equatable, Sendable {
    public var platform: PlatformKind
    public var videoSize: CGSize
    public var cropRect: CGRect

    public init(videoSize: CGSize, platform: PlatformKind) {
        self.platform = platform
        self.videoSize = videoSize

        let targetAspectRatio = platform.aspectRatio
        guard videoSize.width > 0, videoSize.height > 0 else {
            self.cropRect = .zero
            return
        }

        let sourceAspectRatio = videoSize.width / videoSize.height
        if abs(sourceAspectRatio - targetAspectRatio) < 0.0001 {
            self.cropRect = CGRect(origin: .zero, size: videoSize)
        } else if sourceAspectRatio > targetAspectRatio {
            let cropWidth = videoSize.height * targetAspectRatio
            self.cropRect = CGRect(
                x: (videoSize.width - cropWidth) / 2,
                y: 0,
                width: cropWidth,
                height: videoSize.height
            )
        } else {
            let cropHeight = videoSize.width / targetAspectRatio
            self.cropRect = CGRect(
                x: 0,
                y: (videoSize.height - cropHeight) / 2,
                width: videoSize.width,
                height: cropHeight
            )
        }
    }

    public var aspectRatio: CGFloat {
        platform.aspectRatio
    }
}

public struct ExportSelection: Equatable, Codable, Sendable {
    private(set) public var variants: [PlatformVariant]

    public init(variants: [PlatformVariant]) {
        self.variants = variants
    }

    public var enabledVariants: [PlatformVariant] {
        variants.filter(\.exportEnabled)
    }

    public mutating func toggle(_ platform: PlatformKind) {
        guard let index = variants.firstIndex(where: { $0.platform == platform }) else { return }
        variants[index].exportEnabled.toggle()
    }
}

// MARK: - Canvas Layout (Studio 编辑器画布)

/// 画布背景类型
public enum CanvasBackground: Equatable, Codable, Sendable {
    /// 纯色（RGBA，0-1 范围）
    case solidColor(r: Double, g: Double, b: Double, a: Double)
    /// 线性渐变（两个颜色 + 角度 0-360°）
    case linearGradient(
        r1: Double, g1: Double, b1: Double,
        r2: Double, g2: Double, b2: Double,
        angle: Double
    )
    /// 导入图片（本地文件 URL 路径字符串）
    case image(path: String)

    public static var defaultBlack: CanvasBackground {
        .solidColor(r: 0.08, g: 0.08, b: 0.10, a: 1)
    }

public static var defaultPurpleGradient: CanvasBackground {
.linearGradient(r1: 0.18, g1: 0.08, b1: 0.42, r2: 0.05, g2: 0.18, b2: 0.55, angle: 145)
}

public static var studioPresets: [StudioBackgroundPreset] { [
StudioBackgroundPreset(label: "黑", background: .solidColor(r: 0.05, g: 0.05, b: 0.07, a: 1)),
StudioBackgroundPreset(label: "冷蓝渐变", background: .linearGradient(r1: 0.553, g1: 0.651, b1: 1.0, r2: 0.498, g2: 0.847, b2: 1.0, angle: 135)),
StudioBackgroundPreset(label: "蜜桃渐变", background: .linearGradient(r1: 1.0, g1: 0.784, b1: 0.820, r2: 1.0, g2: 0.859, b2: 0.757, angle: 135)),
StudioBackgroundPreset(label: "薄荷渐变", background: .linearGradient(r1: 0.839, g1: 0.953, b1: 0.937, r2: 0.843, g2: 0.894, b2: 1.0, angle: 135)),
StudioBackgroundPreset(label: "白", background: .solidColor(r: 1, g: 1, b: 1, a: 1))
] }

public var isStudioCustomColor: Bool {
guard case .solidColor = self else { return false }
return Self.studioPresets.contains(where: { $0.background == self }) == false
}

public func gradientPointsForSwiftUI() -> (start: CGPoint, end: CGPoint)? {

        guard case let .linearGradient(_, _, _, _, _, _, angle) = self else { return nil }
        return Self.gradientPoints(for: angle, flipY: false)
    }

public func gradientPointsForCoreAnimation() -> (start: CGPoint, end: CGPoint)? {
guard case let .linearGradient(_, _, _, _, _, _, angle) = self else { return nil }
return Self.gradientPoints(for: angle, flipY: true)
}

/// 是否需要在导出时使用 CALayer 渲染背景（渐变/图片无法用 instruction.backgroundColor 表示）
internal var requiresCALayerBackground: Bool {
    switch self {
    case .solidColor:
        return false   // 纯色直接用 instruction.backgroundColor 即可
    case .linearGradient, .image:
        return true
    }
}

/// 是否需要在 Pass 2（PiP 合成）时使用遮罩层挡住 PiP 视频溢出区域
/// 所有背景类型都需要：evenOdd 遮罩层填充背景色，遮挡 PiP cover-fit 可能溢出的视频
public var requiresExportCutoutOverlay: Bool {
    return true
}

private static func gradientPoints(for angle: Double, flipY: Bool) -> (start: CGPoint, end: CGPoint) {

        let rad = angle * .pi / 180
        let dx = cos(rad) * 0.5
        let dy = sin(rad) * 0.5
        let startY = flipY ? (0.5 - dy) : (0.5 + dy)
        let endY = flipY ? (0.5 + dy) : (0.5 - dy)
        return (
            start: CGPoint(x: 0.5 - dx, y: startY),
            end: CGPoint(x: 0.5 + dx, y: endY)
        )
    }
}

public struct ScreenContentGeometry: Equatable, Sendable {
public var visibleRect: CGRect
public var fullRect: CGRect

public init(visibleRect: CGRect, fullRect: CGRect) {
self.visibleRect = visibleRect
self.fullRect = fullRect
}
}

public struct StudioBackgroundPreset: Equatable, Sendable {
public var label: String
public var background: CanvasBackground

public init(label: String, background: CanvasBackground) {
self.label = label
self.background = background
}
}

public struct StudioCustomColorSelection: Equatable, Sendable {
public var hue: Double
public var saturation: Double
public var brightness: Double

public init(hue: Double = 0.61, saturation: Double = 0.46, brightness: Double = 0.92) {
self.hue = Self.clamp01(hue)
self.saturation = Self.clamp01(saturation)
self.brightness = Self.clamp01(brightness)
}

public init?(background: CanvasBackground) {
guard case let .solidColor(r, g, b, _) = background else { return nil }
let hsb = Self.hsb(fromRed: r, green: g, blue: b)
self.init(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)
}

public var canvasBackground: CanvasBackground {
let rgb = Self.rgb(fromHue: hue, saturation: saturation, brightness: brightness)
return .solidColor(r: rgb.red, g: rgb.green, b: rgb.blue, a: 1)
}

public var hexString: String {
let rgb = Self.rgb(fromHue: hue, saturation: saturation, brightness: brightness)
let red = Int((rgb.red * 255).rounded())
let green = Int((rgb.green * 255).rounded())
let blue = Int((rgb.blue * 255).rounded())
return String(format: "#%02X%02X%02X", red, green, blue)
}

private static func clamp01(_ value: Double) -> Double {
min(max(value, 0), 1)
}

private static func rgb(fromHue hue: Double, saturation: Double, brightness: Double) -> (red: Double, green: Double, blue: Double) {
let h = (clamp01(hue) * 6).truncatingRemainder(dividingBy: 6)
let s = clamp01(saturation)
let v = clamp01(brightness)
let sector = Int(floor(h))
let fraction = h - Double(sector)
let p = v * (1 - s)
let q = v * (1 - s * fraction)
let t = v * (1 - s * (1 - fraction))

switch sector {
case 0: return (v, t, p)
case 1: return (q, v, p)
case 2: return (p, v, t)
case 3: return (p, q, v)
case 4: return (t, p, v)
default: return (v, p, q)
}
}

private static func hsb(fromRed red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, brightness: Double) {
let r = clamp01(red)
let g = clamp01(green)
let b = clamp01(blue)
let maxValue = max(r, g, b)
let minValue = min(r, g, b)
let delta = maxValue - minValue
let brightness = maxValue
let saturation = maxValue == 0 ? 0 : delta / maxValue

guard delta > 0 else {
return (0, saturation, brightness)
}

let hue: Double
if maxValue == r {
hue = (((g - b) / delta).truncatingRemainder(dividingBy: 6)) / 6
} else if maxValue == g {
hue = (((b - r) / delta) + 2) / 6
} else {
hue = (((r - g) / delta) + 4) / 6
}

return (hue < 0 ? hue + 1 : hue, saturation, brightness)
}
}

/// 画布上一个可移动/缩放的元素（归一化坐标，0-1 相对于画布）
public struct CanvasElementFrame: Equatable, Codable, Sendable {
/// 元素在画布中心点的归一化位置（0-1）
public var centerX: Double
public var centerY: Double
/// 元素宽度占画布宽度的比例
public var widthRatio: Double
/// 元素高度占画布高度的比例
public var heightRatio: Double

public init(centerX: Double, centerY: Double, widthRatio: Double, heightRatio: Double) {
self.centerX = centerX
self.centerY = centerY
self.widthRatio = widthRatio
self.heightRatio = heightRatio
}

public func normalizedForShape(_ shape: CameraShape, platformAspectRatio: CGFloat) -> CanvasElementFrame {
    guard shape.usesSquarePixels || shape == .rectangle else { return self }
    var frame = self
    let canvasAspect = Double(platformAspectRatio)
    if shape.usesSquarePixels {
        frame.heightRatio = frame.widthRatio * canvasAspect
    } else if let targetAspect = shape.aspectRatio {
        frame.heightRatio = frame.widthRatio * canvasAspect / Double(targetAspect)
    }
    return frame
}

/// 将归一化帧转换为画布尺寸内的实际 CGRect
public func toRect(in canvasSize: CGSize) -> CGRect {
    let w = widthRatio * canvasSize.width
    let h = heightRatio * canvasSize.height
    return CGRect(
        x: centerX * canvasSize.width - w / 2,
        y: centerY * canvasSize.height - h / 2,
        width: w,
        height: h
    )
}

public func screenContentGeometry(in canvasSize: CGSize, crop: ScreenCropRect) -> ScreenContentGeometry {
    let visibleRect = toRect(in: canvasSize)
    return ScreenContentGeometry(
        visibleRect: visibleRect,
        fullRect: crop.contentRect(in: visibleRect)
    )
}

/// 从实际 CGRect 创建归一化帧
public static func from(rect: CGRect, in canvasSize: CGSize) -> CanvasElementFrame {
    guard canvasSize.width > 0, canvasSize.height > 0 else {
        return CanvasElementFrame(centerX: 0.5, centerY: 0.5, widthRatio: 1, heightRatio: 1)
    }
    return CanvasElementFrame(
        centerX: (rect.midX / canvasSize.width).clamped(to: 0...1),
        centerY: (rect.midY / canvasSize.height).clamped(to: 0...1),
        widthRatio: (rect.width / canvasSize.width).clamped(to: 0.05...1),
        heightRatio: (rect.height / canvasSize.height).clamped(to: 0.05...1)
    )
}
}

public enum CanvasResizeMode: Sendable {
case squarePixels
case proportional
case freeform
}

public func resizedCanvasElementFrame(
    startFrame: CanvasElementFrame,
    canvasSize: CGSize,
    translation: CGSize,
    mode: CanvasResizeMode
) -> CanvasElementFrame {
    guard canvasSize.width > 0, canvasSize.height > 0 else { return startFrame }

    let dx = translation.width / canvasSize.width
    let dy = translation.height / canvasSize.height
    let delta = (dx + dy) / 2

    switch mode {
    case .squarePixels:
        let ar = canvasSize.width / canvasSize.height
        let newW = max(0.06, min(startFrame.widthRatio + dx * 2, 0.99))
        let newH = newW * Double(ar)
        return CanvasElementFrame(
            centerX: startFrame.centerX,
            centerY: startFrame.centerY,
            widthRatio: newW,
            heightRatio: newH
        )
    case .proportional:
        let aspect = startFrame.widthRatio / max(startFrame.heightRatio, 0.001)
        let newH = max(0.06, min(startFrame.heightRatio + delta, 0.95))
        let newW = max(0.06, min(newH * aspect, 0.99))
        return CanvasElementFrame(
            centerX: startFrame.centerX,
            centerY: startFrame.centerY,
            widthRatio: newW,
            heightRatio: newH
        )
    case .freeform:
        let newW = max(0.06, min(startFrame.widthRatio + dx * 2, 0.99))
        let newH = max(0.06, min(startFrame.heightRatio + dy * 2, 0.95))
        return CanvasElementFrame(
            centerX: startFrame.centerX,
            centerY: startFrame.centerY,
            widthRatio: newW,
            heightRatio: newH
        )
    }
}

/// 屏幕录像的源区域裁剪（0-1 归一化，对应源视频的可见区域）
public struct ScreenCropRect: Equatable, Codable, Sendable {
    /// 源视频可见区域左侧起点（0=左边）
    public var minX: Double
    /// 源视频可见区域顶部起点（0=上边）
    public var minY: Double
    /// 源视频可见区域宽度（1=整宽）
    public var width: Double
    /// 源视频可见区域高度（1=整高）
    public var height: Double

    public init(minX: Double = 0, minY: Double = 0, width: Double = 1, height: Double = 1) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public static let full = ScreenCropRect(minX: 0, minY: 0, width: 1, height: 1)

    public var isFullFrame: Bool {
        minX == 0 && minY == 0 && width == 1 && height == 1
    }

    /// 转换为 AVFoundation 使用的 CGRect（原点左上角）
    public func toCGRect() -> CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }

    public func contentRect(in visibleRect: CGRect) -> CGRect {
        let safeWidth = max(width, 0.001)
        let safeHeight = max(height, 0.001)
        let fullWidth = visibleRect.width / safeWidth
        let fullHeight = visibleRect.height / safeHeight
        return CGRect(
            x: visibleRect.minX - minX * fullWidth,
            y: visibleRect.minY - minY * fullHeight,
            width: fullWidth,
            height: fullHeight
        )
    }

    public func composed(with innerCrop: ScreenCropRect) -> ScreenCropRect {
        ScreenCropRect(
            minX: minX + innerCrop.minX * width,
            minY: minY + innerCrop.minY * height,
            width: width * innerCrop.width,
            height: height * innerCrop.height
        )
    }
}

public func makeClickTriggeredAutoZoomSegments(
    clicks: [SmartAutoZoomClickEvent],
    durationSeconds: Double,
    settings: SmartAutoZoomSettings
) -> [SmartAutoZoomSegment] {
    guard settings.isEnabled, durationSeconds > 0 else { return [] }

    let duration = max(durationSeconds, 0)
    let sortedClicks = clicks.sorted { $0.timestampSeconds < $1.timestampSeconds }
    var segments: [SmartAutoZoomSegment] = []

    for click in sortedClicks {
        let focus = min(max(click.timestampSeconds, 0), duration)
        let segment = SmartAutoZoomSegment(
            startSeconds: max(0, focus - max(settings.leadInSeconds, 0)),
            focusSeconds: focus,
            holdEndSeconds: min(duration, focus + max(settings.holdSeconds, 0)),
            endSeconds: min(duration, focus + max(settings.holdSeconds, 0) + max(settings.releaseSeconds, 0)),
            normalizedX: click.normalizedX,
            normalizedY: click.normalizedY,
            zoomScale: settings.sanitizedZoomScale
        )

        if let last = segments.last,
           segment.startSeconds <= last.endSeconds + max(settings.mergeGapSeconds, 0) {
            segments[segments.count - 1] = SmartAutoZoomSegment(
                startSeconds: min(last.startSeconds, segment.startSeconds),
                focusSeconds: segment.focusSeconds,
                holdEndSeconds: segment.holdEndSeconds,
                endSeconds: segment.endSeconds,
                normalizedX: segment.normalizedX,
                normalizedY: segment.normalizedY,
                zoomScale: segment.zoomScale
            )
        } else {
            segments.append(segment)
        }
    }

    return segments
}

public func makeSmartAutoZoomCrop(at timeSeconds: Double, segments: [SmartAutoZoomSegment]) -> ScreenCropRect {
    guard let segment = segments.last(where: { timeSeconds >= $0.startSeconds && timeSeconds <= $0.endSeconds }) else {
        return .full
    }

    let targetCrop = targetSmartAutoZoomCrop(
        normalizedX: segment.normalizedX,
        normalizedY: segment.normalizedY,
        zoomScale: segment.zoomScale
    )

    if timeSeconds <= segment.focusSeconds {
        // Zoom in 阶段：easeOutCubic —— 快速拉近、平滑停止，避免线性卡顿感
        let duration = max(segment.focusSeconds - segment.startSeconds, 0.0001)
        let progress = max(0, min((timeSeconds - segment.startSeconds) / duration, 1))
        return interpolateScreenCrop(from: .full, to: targetCrop, progress: progress, easing: easeOutCubic)
    }

    if timeSeconds <= segment.holdEndSeconds {
        return targetCrop
    }

    // Zoom out 阶段：easeInCubic —— 缓缓开始退出，自然过渡
    let duration = max(segment.endSeconds - segment.holdEndSeconds, 0.0001)
    let progress = max(0, min((timeSeconds - segment.holdEndSeconds) / duration, 1))
    return interpolateScreenCrop(from: targetCrop, to: .full, progress: progress, easing: easeInCubic)
}

public func makeComposedSmartAutoZoomCrop(
    baseCrop: ScreenCropRect,
    at timeSeconds: Double,
    segments: [SmartAutoZoomSegment]
) -> ScreenCropRect {
    baseCrop.composed(with: makeSmartAutoZoomCrop(at: timeSeconds, segments: segments))
}

public func makeComposedSmartAutoZoomCrop(
    baseCrop: ScreenCropRect,
    at timeSeconds: Double,
    clicks: [SmartAutoZoomClickEvent],
    durationSeconds: Double,
    settings: SmartAutoZoomSettings
) -> ScreenCropRect {
    let segments = makeClickTriggeredAutoZoomSegments(
        clicks: clicks,
        durationSeconds: durationSeconds,
        settings: settings
    )
    return makeComposedSmartAutoZoomCrop(baseCrop: baseCrop, at: timeSeconds, segments: segments)
}

private func targetSmartAutoZoomCrop(normalizedX: Double, normalizedY: Double, zoomScale: Double) -> ScreenCropRect {
    let safeZoomScale = max(zoomScale, 1)
    let cropWidth = 1 / safeZoomScale
    let cropHeight = 1 / safeZoomScale
    let minX = (normalizedX - cropWidth / 2).clamped(to: 0...(1 - cropWidth))
    let minY = (normalizedY - cropHeight / 2).clamped(to: 0...(1 - cropHeight))
    return ScreenCropRect(minX: minX, minY: minY, width: cropWidth, height: cropHeight)
}

/// easeOutCubic：先快后慢，适合 zoom in（镜头快速拉近后平滑停止）
private func easeOutCubic(_ t: Double) -> Double {
    let t1 = 1 - t
    return 1 - t1 * t1 * t1
}

/// easeInCubic：先慢后快，适合 zoom out（镜头缓缓开始退出）
private func easeInCubic(_ t: Double) -> Double {
    return t * t * t
}

/// easeInOutCubic：两端慢中间快，通用过渡
private func easeInOutCubic(_ t: Double) -> Double {
    if t < 0.5 { return 4 * t * t * t }
    let u = -2 * t + 2
    return 1 - u * u * u / 2
}

private func interpolateScreenCrop(
    from start: ScreenCropRect,
    to end: ScreenCropRect,
    progress: Double,
    easing: (Double) -> Double = { $0 }
) -> ScreenCropRect {
    let t = easing(progress.clamped(to: 0...1))
    return ScreenCropRect(
        minX: start.minX + (end.minX - start.minX) * t,
        minY: start.minY + (end.minY - start.minY) * t,
        width: start.width + (end.width - start.width) * t,
        height: start.height + (end.height - start.height) * t
    )
}

/// 整体画布布局（针对某个平台）
public struct CanvasLayout: Equatable, Codable, Sendable {
    public var platform: PlatformKind
    public var background: CanvasBackground
    /// 屏幕录像层（归一化）
    public var screenFrame: CanvasElementFrame
    /// 屏幕录像源区域裁剪（0-1）；full = 不裁剪
    public var screenCrop: ScreenCropRect
    /// 摄像头 PiP 层（归一化），nil = 不显示
    public var pipFrame: CanvasElementFrame?
    /// PiP 形状
    public var pipShape: CameraShape

    public init(
        platform: PlatformKind,
        background: CanvasBackground = .defaultBlack,
        screenFrame: CanvasElementFrame,
        screenCrop: ScreenCropRect = .full,
        pipFrame: CanvasElementFrame? = nil,
        pipShape: CameraShape = .circle
    ) {
        self.platform = platform
        self.background = background
        self.screenFrame = screenFrame
        self.screenCrop = screenCrop
        self.pipFrame = pipFrame
        self.pipShape = pipShape
    }

    /// 根据平台生成默认布局
    public static func defaultLayout(for platform: PlatformKind, hasPiP: Bool) -> CanvasLayout {
        let ar = platform.aspectRatio  // W/H
        // 屏幕录像：按宽填满，高度按 16:9 源视频比例计算，垂直居中偏上
        let screenW: Double = 1.0
        let screenH: Double = screenW / (16.0 / 9.0) / ar  // 相对高度
        let screenCY: Double = hasPiP ? 0.42 : 0.5          // 有 PiP 时略微偏上

        var layout = CanvasLayout(
            platform: platform,
            background: .defaultBlack,
            screenFrame: CanvasElementFrame(
                centerX: 0.5,
                centerY: screenCY,
                widthRatio: screenW,
                heightRatio: min(screenH, 1.0)
            ),
            pipFrame: nil,
            pipShape: .circle
        )

        if hasPiP {
            // PiP 默认放右下角，约占画布宽 30%
            // heightRatio 需按平台宽高比校正，使像素上是正方形：
            //   实际像素宽 = pipW * canvasW
            //   实际像素高 = pipH * canvasH = pipH * canvasW / ar
            //   令两者相等 → pipH = pipW * ar
            let pipW: Double = 0.30
            let pipH: Double = pipW * Double(ar)  // 正方形像素
            layout.pipFrame = CanvasElementFrame(
                centerX: 0.78,
                centerY: 0.82,
                widthRatio: pipW,
                heightRatio: pipH
            )
        }
        return layout
    }

/// 根据当前形状重新计算 PiP 的高宽比例。
/// 圆形/方形保持像素正方形，矩形保持横版比例。
public mutating func normalizePipFrameForCurrentShape() {
guard let pip = pipFrame else { return }
pipFrame = pip.normalizedForShape(pipShape, platformAspectRatio: platform.aspectRatio)
}
}


private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
