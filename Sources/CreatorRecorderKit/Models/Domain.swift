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
        let maxDimension = max(min(region.size.width - inset, region.size.height - inset), Self.minimumSize)
        let side = min(max(size.width, Self.minimumSize), maxDimension)
        let clampedSize = CGSize(width: side, height: side)
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

    public func withShape(_ shape: CameraShape) -> CameraOverlayLayout {
        var copy = self
        copy.style.shape = shape
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

public enum RecordingState: Equatable, Sendable {
    case idle
    case recording
    case failed(String)
}

public struct RecordingResult: Equatable, Codable, Sendable {
    public var fileURL: URL
    public var durationSeconds: Double
    public var fileSizeBytes: Int64

    public init(fileURL: URL, durationSeconds: Double, fileSizeBytes: Int64) {
        self.fileURL = fileURL
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
    }

    public var isPreviewAvailable: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
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

public struct CaptureSessionConfiguration: Equatable, Sendable {
    public var display: DisplaySource
    public var region: CaptureRegion
    public var canvasSize: CGSize
    public var cameraOverlay: CameraOverlayLayout?
    public var microphoneEnabled: Bool
    public var systemAudioEnabled: Bool

    public init(
        display: DisplaySource,
        region: CaptureRegion,
        canvasSize: CGSize,
        cameraOverlay: CameraOverlayLayout?,
        microphoneEnabled: Bool,
        systemAudioEnabled: Bool
    ) {
        self.display = display
        self.region = region
        self.canvasSize = canvasSize
        self.cameraOverlay = cameraOverlay
        self.microphoneEnabled = microphoneEnabled
        self.systemAudioEnabled = systemAudioEnabled
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
