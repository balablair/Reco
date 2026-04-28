import Foundation
import CoreGraphics
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Reco
@testable import RecoKit

private func expectClose(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.0001) {
    #expect(abs(lhs - rhs) <= tolerance)
}

private func expectClose(_ lhs: ScreenCropRect, _ rhs: ScreenCropRect, tolerance: CGFloat = 0.0001) {
    expectClose(lhs.minX, rhs.minX, tolerance: tolerance)
    expectClose(lhs.minY, rhs.minY, tolerance: tolerance)
    expectClose(lhs.width, rhs.width, tolerance: tolerance)
    expectClose(lhs.height, rhs.height, tolerance: tolerance)
}

private func expectClose(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001) {
    #expect(abs(lhs - rhs) <= tolerance)
}

private func makeSolidTestImage(
    width: Int,
    height: Int,
    red: UInt8,
    green: UInt8,
    blue: UInt8,
    alpha: UInt8 = 255
) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        pixels[index] = red
        pixels[index + 1] = green
        pixels[index + 2] = blue
        pixels[index + 3] = alpha
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        return nil
    }
    return ctx.makeImage()
}

private func sampleRGBA(in image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8)? {
    guard let provider = image.dataProvider,
          let data = provider.data,
          let bytes = CFDataGetBytePtr(data) else {
        return nil
    }

    let bytesPerRow = image.bytesPerRow
    let offset = y * bytesPerRow + x * 4
    let blue = bytes[offset]
    let green = bytes[offset + 1]
    let red = bytes[offset + 2]
    let alpha = bytes[offset + 3]
    return (red, green, blue, alpha)
}

@Test("平台变体从模板初始化")
func platformVariantUsesTemplateDefaults() {
    let template = ProjectTemplate.xiaohongshu
    let variant = PlatformVariant(template: template)

    #expect(variant.platform == .xiaohongshu)
    #expect(variant.aspectRatio == .portraitStory)
    #expect(variant.safeAreaPreset == .xiaohongshu)
    #expect(variant.cameraStyle.shape == .roundedCard)
}

@Test("导出遮罩会覆盖所有背景类型")
func canvasBackgroundRequiresExportCutoutOverlay() {
    let backgrounds: [CanvasBackground] = [
        .solidColor(r: 0.2, g: 0.8, b: 0.2, a: 1),
        .linearGradient(r1: 0.1, g1: 0.2, b1: 0.3, r2: 0.4, g2: 0.5, b2: 0.6, angle: 45),
        .image(path: "/tmp/demo.png")
    ]

    for background in backgrounds {
        #expect(background.requiresExportCutoutOverlay)
    }
}

@Test("编辑器只把非预设纯色识别为自定义颜色")
func canvasBackgroundDetectsCustomStudioColor() {
    #expect(CanvasBackground.defaultBlack.isStudioCustomColor == false)
    #expect(CanvasBackground.defaultPurpleGradient.isStudioCustomColor == false)
    #expect(CanvasBackground.solidColor(r: 0.31, g: 0.42, b: 0.53, a: 1).isStudioCustomColor)
    #expect(CanvasBackground.image(path: "/tmp/demo.png").isStudioCustomColor == false)
}

@Test("Studio 预设包含灵感渐变和中性色")
func studioBackgroundPresetsUseInspirationPalette() {
    let presets = CanvasBackground.studioPresets

    #expect(presets.map(\ .label) == ["黑", "石墨", "冷蓝渐变", "蜜桃渐变", "薄荷渐变", "白"])
    #expect(presets[0].background == .solidColor(r: 0.05, g: 0.05, b: 0.07, a: 1))
    #expect(presets[1].background == .solidColor(r: 0.16, g: 0.17, b: 0.20, a: 1))
    #expect(presets[2].background == .linearGradient(r1: 0.553, g1: 0.651, b1: 1.0, r2: 0.498, g2: 0.847, b2: 1.0, angle: 135))
    #expect(presets[3].background == .linearGradient(r1: 1.0, g1: 0.784, b1: 0.820, r2: 1.0, g2: 0.859, b2: 0.757, angle: 135))
    #expect(presets[4].background == .linearGradient(r1: 0.839, g1: 0.953, b1: 0.937, r2: 0.843, g2: 0.894, b2: 1.0, angle: 135))
    #expect(presets[5].background == .solidColor(r: 1, g: 1, b: 1, a: 1))
}

@Test("Studio 自定义取色会输出纯色背景并保留色值")
func studioCustomColorSelectionProducesSolidCanvasBackground() throws {
    let selection = StudioCustomColorSelection(hue: 0.61, saturation: 0.46, brightness: 0.92)
    let background = selection.canvasBackground
    let roundTrip = try #require(StudioCustomColorSelection(background: background))

    #expect(background.isStudioCustomColor)
    expectClose(roundTrip.hue, selection.hue, tolerance: 0.02)
    expectClose(roundTrip.saturation, selection.saturation, tolerance: 0.02)
    expectClose(roundTrip.brightness, selection.brightness, tolerance: 0.02)
    #expect(selection.hexString.hasPrefix("#"))
    #expect(selection.hexString.count == 7)
}

@Test("Studio 自定义取色不会把渐变背景识别成纯色")
func studioCustomColorSelectionIgnoresGradientBackground() {
    #expect(StudioCustomColorSelection(background: .defaultPurpleGradient) == nil)
}

@Test("平台导出完成状态会生成精简摘要卡片")
func variantExportStatusCardUsesSummaryPresentation() {
    let model = makeVariantExportStatusCardModel(.completed([
        ExportedVariantResult(
            platform: .douyin,
            fileURL: URL(fileURLWithPath: "/tmp/douyin.mp4"),
            renderSize: .init(width: 1080, height: 1920),
            fileSizeBytes: 16_000_000
        ),
        ExportedVariantResult(
            platform: .bilibili,
            fileURL: URL(fileURLWithPath: "/tmp/bilibili.mp4"),
            renderSize: .init(width: 1920, height: 1080),
            fileSizeBytes: 18_000_000
        )
    ]))

    #expect(model?.tone == .success)
    #expect(model?.title == "已导出 2 个平台")
    #expect(model?.items.map(\ .title) == ["Douyin", "Bilibili"])
}

@Test("原素材导出完成状态会生成素材摘要卡片")
func sourceExportStatusCardUsesAssetSummaryPresentation() {
    let model = makeSourceExportStatusCardModel(.completed([
        ExportedSourceAsset(kind: .screen, fileURL: URL(fileURLWithPath: "/tmp/screen.mp4"), fileSizeBytes: 32_000_000),
        ExportedSourceAsset(kind: .camera, fileURL: URL(fileURLWithPath: "/tmp/camera.mp4"), fileSizeBytes: 11_000_000)
    ]))

    #expect(model?.tone == .info)
    #expect(model?.title == "原素材已就绪")
    #expect(model?.items.map(\ .title) == ["Screen", "Camera"])
}

@Test("平台导出完成会生成轻提示模型")
func variantExportStateProducesToastModel() {
    let fileURL = URL(fileURLWithPath: "/tmp/xiaohongshu.mp4")
    let model = makeVariantExportToastModel(.completed([
        ExportedVariantResult(
            platform: .xiaohongshu,
            fileURL: fileURL,
            renderSize: .init(width: 1080, height: 1920),
            fileSizeBytes: 21_000_000
        )
    ]))

    #expect(model?.message == "已导出 1 个平台")
    #expect(model?.actionTitle == "查看")
    #expect(model?.targetURL == fileURL)
}

@Test("导出失败不会生成轻提示模型")
func failedVariantExportStateDoesNotProduceToastModel() {
    #expect(makeVariantExportToastModel(.failed("boom")) == nil)
}

@Test("原素材导出完成会生成轻提示模型")
func sourceExportStateProducesToastModel() {
    let fileURL = URL(fileURLWithPath: "/tmp/screen.mov")
    let model = makeSourceExportToastModel(.completed([
        ExportedSourceAsset(kind: .screen, fileURL: fileURL, fileSizeBytes: 32_000_000)
    ]))

    #expect(model?.message == "原素材已导出")
    #expect(model?.actionTitle == "查看")
    #expect(model?.targetURL == fileURL)
}

@Test("录制完成浮层卡片使用精简文案")
func recordingCompletionCardUsesCompactPresentation() {
    let model = makeRecordingCompletionCardModel(
        recordingElapsedSeconds: 10,
        sourceExportState: .idle
    )

    #expect(model.eyebrow == "Recording Finished")
    #expect(model.title == "录制完成")
    #expect(model.durationLabel == "00:10")
    #expect(model.exportSourceButtonTitle == "导出原素材")
    #expect(model.exportSourceButtonEnabled)
    #expect(model.primaryActionTitle == "打开 Studio")
}

@Test("录制完成浮层卡片会反映原素材导出进度")
func recordingCompletionCardReflectsSourceExportProgress() {
    let model = makeRecordingCompletionCardModel(
        recordingElapsedSeconds: 65,
        sourceExportState: .exporting
    )

    #expect(model.durationLabel == "01:05")
    #expect(model.exportSourceButtonTitle == "导出中...")
    #expect(model.exportSourceButtonEnabled == false)
}

@Test("录制完成浮层卡片会反映原素材已导出状态")
func recordingCompletionCardReflectsCompletedSourceExport() {
    let model = makeRecordingCompletionCardModel(
        recordingElapsedSeconds: 125,
        sourceExportState: .completed([
            ExportedSourceAsset(kind: .screen, fileURL: URL(fileURLWithPath: "/tmp/screen.mp4"), fileSizeBytes: 32_000_000)
        ])
    )

    #expect(model.durationLabel == "02:05")
    #expect(model.exportSourceButtonTitle == "已导出原素材")
    #expect(model.exportSourceButtonEnabled)
}

@Test("录制完成浮层卡片在无视频时回退到占位预览")
@MainActor
func recordingCompletionCardShowsPlaceholderThumbnailWhenMissingRecording() {
    let viewModel = AppViewModel()
    let view = CompletionCardView(
        viewModel: viewModel,
        onRedo: {},
        onExportSource: {},
        onOpenInStudio: {}
    )

    #expect(String(describing: view.thumbnailImage) == "nil")
}

@Test("录制完成浮层卡片在有视频时生成预览缩略图")
@MainActor
func recordingCompletionCardGeneratesThumbnailWhenRecordingExists() {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing-preview.mp4")
    let viewModel = AppViewModel()
    viewModel.latestRecording = RecordingResult(
        fileURL: fileURL,
        durationSeconds: 1,
        fileSizeBytes: 1_024
    )

    let view = CompletionCardView(
        viewModel: viewModel,
        onRedo: {},
        onExportSource: {},
        onOpenInStudio: {}
    )

    #expect(String(describing: view.thumbnailImage) == "nil")
}

@Test("提词器默认只保留文稿和滚动速度状态")
@MainActor
func teleprompterStateStaysMinimalAfterRemovingSpeechSync() {
    let viewModel = AppViewModel()

    #expect(viewModel.teleprompterText.isEmpty)
    #expect(viewModel.teleprompterScrollSpeed == 40)
}

@Test("Prep 遮罩会沿用与边框一致的圆角挖空")
func prepDimmingMaskUsesRoundedSelectionCutout() {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
    let selection = CGRect(x: 50, y: 50, width: 100, height: 100)
    let path = makePrepSelectionMaskPath(bounds: bounds, selectionRect: selection)

    #expect(path.contains(CGPoint(x: 20, y: 20), using: .evenOdd))
    #expect(path.contains(CGPoint(x: 100, y: 100), using: .evenOdd) == false)
    #expect(path.contains(CGPoint(x: 51, y: 51), using: .evenOdd))
}

@Test("Prep 遮罩挖空会向内收齐到虚线边框")
func prepDimmingMaskInsetsCutoutToMatchOutlineStroke() {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
    let selection = CGRect(x: 50, y: 50, width: 100, height: 100)
    let path = makePrepSelectionMaskPath(bounds: bounds, selectionRect: selection)

    #expect(path.contains(CGPoint(x: 50.2, y: 100), using: .evenOdd))
    #expect(path.contains(CGPoint(x: 100, y: 50.2), using: .evenOdd))
    #expect(path.contains(CGPoint(x: 50.9, y: 100), using: .evenOdd) == false)
    #expect(path.contains(CGPoint(x: 100, y: 50.9), using: .evenOdd) == false)
}

@Test("Prep 遮罩会把 AppKit 选区转换为顶部原点坐标")
func prepDimmingDisplayRectFlipsYFromAppKitCoordinates() {
    let screen = CGRect(x: 10, y: 20, width: 300, height: 200)
    let selection = CGRect(x: 40, y: 50, width: 120, height: 80)
    let displayRect = makePrepDisplayRect(selectionFrame: selection, screenFrame: screen)

    #expect(displayRect.origin.x == 30)
    #expect(displayRect.origin.y == 90)
    #expect(displayRect.width == 120)
    #expect(displayRect.height == 80)
}

@Test("导出视频位移不会被缩放重复放大")
func exportPlacementTransformKeepsTranslationIndependentFromScale() {
    let transform = makePlacedTransform(
        base: .identity,
        scale: 0.5,
        tx: 100,
        ty: 200
    )

    let origin = CGPoint.zero.applying(transform)
    let point = CGPoint(x: 400, y: 300).applying(transform)

    expectClose(origin.x, 100)
    expectClose(origin.y, 200)
    expectClose(point.x, 300)
    expectClose(point.y, 350)
}

@Test("导出视频位移会保留旋转素材的基础平移")
func exportPlacementTransformPreservesBaseTranslation() {
    let transform = makePlacedTransform(
        base: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 720, ty: 0),
        scale: 0.5,
        tx: 100,
        ty: 200
    )

    let transformedRect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        .applying(transform)
        .standardized

    expectClose(transformedRect.minX, 100)
    expectClose(transformedRect.minY, 200)
    expectClose(transformedRect.width, 360)
    expectClose(transformedRect.height, 640)
}

@Test("导出帧合成会保留可见区域外的背景")
func compositeFrameImagePreservesBackgroundOutsideClip() throws {
    let canvasSize = CGSize(width: 10, height: 10)
    let background = try #require(makeSolidTestImage(width: 10, height: 10, red: 255, green: 0, blue: 0))
    let overlay = try #require(makeSolidTestImage(width: 10, height: 10, red: 0, green: 0, blue: 0))
    let clipRect = renderRectInImageCoordinates(
        CGRect(x: 2, y: 2, width: 4, height: 4),
        canvasSize: canvasSize
    )
    let clipPath = CGPath(rect: clipRect, transform: nil)

    let image = try #require(
        compositeFrameImage(
            canvasSize: canvasSize,
            backgroundImage: background,
            overlayImage: overlay,
            overlayClipPath: clipPath
        )
    )

    let outsidePixel = try #require(sampleRGBA(in: image, x: 1, y: 1))
    let insidePixel = try #require(sampleRGBA(in: image, x: 3, y: 5))

    #expect(outsidePixel.0 == 255)
    #expect(outsidePixel.1 == 0)
    #expect(outsidePixel.2 == 0)
    #expect(insidePixel.0 == 0)
    #expect(insidePixel.1 == 0)
    #expect(insidePixel.2 == 0)
}

@Test("导出帧合成会直接绘制纯色画布背景")
func compositeFrameImageRendersCanvasBackground() throws {
    let canvasSize = CGSize(width: 8, height: 8)
    let image = try #require(
        compositeFrameImage(
            canvasSize: canvasSize,
            background: .solidColor(r: 0.2, g: 0.4, b: 0.8, a: 1),
            overlayImage: nil,
            overlayClipPath: nil
        )
    )

    let pixel = try #require(sampleRGBA(in: image, x: 4, y: 4))
    #expect(abs(Int(pixel.0) - 51) <= 2)
    #expect(abs(Int(pixel.1) - 102) <= 2)
    #expect(abs(Int(pixel.2) - 204) <= 2)
    #expect(pixel.3 == 255)
}

@Test("导出 PiP 几何与预览一致")
func pipPlacementGeometryMatchesPreviewModel() {
    let geometry = makePipPlacementGeometry(
        sourceSize: .init(width: 1280, height: 720),
        pipFrame: .init(centerX: 0.743715, centerY: 0.755537, widthRatio: 0.387717, heightRatio: 0.218091),
        renderSize: .init(width: 1080, height: 1920)
    )

    expectClose(geometry.visibleRect.minX, 593.845, tolerance: 0.001)
    expectClose(geometry.visibleRect.minY, 1241.26, tolerance: 0.01)
    expectClose(geometry.visibleRect.width, 418.734, tolerance: 0.001)
    expectClose(geometry.visibleRect.height, 418.734, tolerance: 0.001)
    expectClose(geometry.scale, 0.581575, tolerance: 0.0001)
    expectClose(geometry.tx, 431.003, tolerance: 0.001)
    expectClose(geometry.ty, 1241.26, tolerance: 0.01)
}

@Test("导出 PiP 形状圆角与预览一致")
func exportPipCornerRadiusMatchesPreviewModel() {
    #expect(pipCornerRadius(for: .circle, in: .init(width: 240, height: 240)) == 120)
    #expect(pipCornerRadius(for: .roundedCard, in: .init(width: 240, height: 240)) == 18)
    #expect(pipCornerRadius(for: .square, in: .init(width: 240, height: 240)) == 6)
    #expect(pipCornerRadius(for: .rectangle, in: .init(width: 320, height: 180)) == 12)
}

@Test("PiP 预览圆角会按实际显示尺寸计算")
func previewPipCornerRadiusUsesRenderedFrameSize() {
    let frame = CanvasElementFrame(centerX: 0.5, centerY: 0.5, widthRatio: 0.2, heightRatio: 0.1)
    let canvasSize = CGSize(width: 400, height: 800)

    #expect(pipPreviewCornerRadius(for: .circle, frame: frame, in: canvasSize) == 40)
    #expect(pipPreviewCornerRadius(for: .rectangle, frame: frame, in: canvasSize) == 12)
}

@Test("导出 PiP 裁剪路径覆盖所有形状")
func exportPipClipPathExistsForEveryShape() throws {
    let squareRect = CGRect(x: 10, y: 20, width: 240, height: 240)
    for shape in [CameraShape.circle, .roundedCard, .square] {
        let path = try #require(makePipClipPath(shape: shape, rect: squareRect))
        #expect(path.boundingBoxOfPath.equalTo(squareRect))
    }

    let rectangleRect = CGRect(x: 30, y: 40, width: 320, height: 180)
    let rectanglePath = try #require(makePipClipPath(shape: .rectangle, rect: rectangleRect))
    #expect(rectanglePath.boundingBoxOfPath.equalTo(rectangleRect))
}

@Test("自由矩形 PiP resize 允许宽高独立变化")
func canvasElementFreeformResizeChangesWidthAndHeightIndependently() {
    let resized = resizedCanvasElementFrame(
        startFrame: CanvasElementFrame(centerX: 0.5, centerY: 0.5, widthRatio: 0.3, heightRatio: 0.2),
        canvasSize: CGSize(width: 1000, height: 1000),
        translation: CGSize(width: 100, height: 50),
        mode: .freeform
    )

    expectClose(resized.widthRatio, 0.5)
    expectClose(resized.heightRatio, 0.3)
}

@Test("PiP 导出优先选择摄像头音轨")
func pipExportPrefersCameraAudioWhenAvailable() {
    #expect(preferredPipAudioSource(baseHasAudio: true, cameraHasAudio: true) == .camera)
}

@Test("PiP 导出在无摄像头音轨时回退到底层音轨")
func pipExportFallsBackToBaseAudioWhenCameraAudioMissing() {
    #expect(preferredPipAudioSource(baseHasAudio: true, cameraHasAudio: false) == .base)
    #expect(preferredPipAudioSource(baseHasAudio: false, cameraHasAudio: false) == .none)
}

@Test("Studio 预览音频优先跟随摄像头")
func studioPreviewAudioPrefersCameraWhenAvailable() {
    #expect(preferredStudioPreviewAudioSource(hasScreenAudio: true, hasCameraAudio: true) == .camera)
    #expect(preferredStudioPreviewAudioSource(hasScreenAudio: true, hasCameraAudio: false) == .screen)
    #expect(preferredStudioPreviewAudioSource(hasScreenAudio: false, hasCameraAudio: true) == .camera)
    #expect(preferredStudioPreviewAudioSource(hasScreenAudio: false, hasCameraAudio: false) == .none)
}

@Test("菜单栏图标主按钮会映射为重开主界面动作")
func statusItemPrimaryTapMapsToReopenAction() {
    #expect(RecoStatusItemAction.primaryButtonTap.resolvedIntent == .reopenPrimaryInterface)
}

@Test("菜单栏左键点击默认执行重开主界面")
func statusItemLeftClickDefaultsToPrimaryAction() {
    #expect(statusItemPrimaryClickIntent() == .reopenPrimaryInterface)
}

@Test("菜单栏图标菜单项包含退出动作")
func statusItemQuitMenuMapsToTerminateAction() {
    #expect(RecoStatusItemAction.quitMenuItem.resolvedIntent == .terminateApp)
}

@Test("播放结束后主按钮切换为重播图标")
@MainActor
func playbackButtonShowsReplayWhenFinished() {
let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
viewModel.latestRecording = RecordingResult(
fileURL: URL(fileURLWithPath: "/tmp/demo.mp4"),
durationSeconds: 12,
fileSizeBytes: 1_024
)

#expect(playbackPrimaryButtonSymbol(for: viewModel) == "play.fill")
viewModel.handlePlaybackFinished()
#expect(playbackPrimaryButtonSymbol(for: viewModel) == "arrow.clockwise")
viewModel.togglePlayback()
#expect(playbackPrimaryButtonSymbol(for: viewModel) == "pause.fill")
}

@Test("未播完时主按钮保持普通播放图标")
@MainActor
func playbackPrimaryButtonStaysPlayDuringNormalPlaybackStates() {
let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
viewModel.latestRecording = RecordingResult(
fileURL: URL(fileURLWithPath: "/tmp/demo.mp4"),
durationSeconds: 12,
fileSizeBytes: 1_024
)
viewModel.playbackPositionSeconds = 3

#expect(playbackPrimaryButtonSymbol(for: viewModel) == "play.fill")
viewModel.playbackState = .playing
#expect(playbackPrimaryButtonSymbol(for: viewModel) == "pause.fill")
}

@Test("播完后重播会立刻把时间标签重置到 0:00")
@MainActor
func replayResetsPlaybackLabelImmediately() {
let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
viewModel.latestRecording = RecordingResult(
fileURL: URL(fileURLWithPath: "/tmp/demo.mp4"),
durationSeconds: 12,
fileSizeBytes: 1_024
)
viewModel.handlePlaybackFinished()

viewModel.togglePlayback()

#expect(viewModel.currentPlaybackTimeLabel == "00:00")
#expect(viewModel.playbackProgress == 0)
}


@Test("导出音频 reader 使用 PCM 输出避免 writer 崩溃")
func exportAudioReaderUsesLinearPCMSettings() {
    let settings = exportAudioReaderOutputSettings()

    #expect(settings[AVFormatIDKey as String] as? UInt32 == kAudioFormatLinearPCM)
    #expect(settings[AVLinearPCMBitDepthKey as String] as? Int == 16)
    #expect(settings[AVLinearPCMIsBigEndianKey as String] as? Bool == false)
    #expect(settings[AVLinearPCMIsNonInterleaved as String] as? Bool == false)
}

@Test("PiP 导出会沿用 trimStart 对齐摄像头素材")
func pipSourceTimeRangeStartsAtTrimOffset() {
    let range = pipSourceTimeRange(
        assetDuration: CMTime(seconds: 20, preferredTimescale: 600),
        trimStart: CMTime(seconds: 5, preferredTimescale: 600),
        trimmedDuration: CMTime(seconds: 8, preferredTimescale: 600)
    )

    #expect(range?.start.seconds == 5)
    #expect(range?.duration.seconds == 8)
}

@Test("PiP 导出在 trimStart 超出摄像头时长时跳过 PiP")
func pipSourceTimeRangeReturnsNilWhenTrimStartsAfterCameraEnds() {
    let range = pipSourceTimeRange(
        assetDuration: CMTime(seconds: 4, preferredTimescale: 600),
        trimStart: CMTime(seconds: 5, preferredTimescale: 600),
        trimmedDuration: CMTime(seconds: 8, preferredTimescale: 600)
    )

    #expect(range == nil)
}

@Test("导出几何函数与预览模型完全一致")
func exportGeometryMatchesPreviewModel() {
    // 验证导出和预览使用完全相同的几何计算公式
    let sourceSize = CGSize(width: 2940, height: 1912)
    let screenFrame = CanvasElementFrame(
        centerX: 0.5, centerY: 0.460833, widthRatio: 1, heightRatio: 0.390059
    )
    let crop = ScreenCropRect(
        minX: 0.14274, minY: 0.0454349, width: 0.85726, height: 0.880632
    )
    let renderSize = CGSize(width: 1080, height: 1920)

    // 预览侧的几何（EditorScreenView 用的是同一套）
    let previewGeometry = screenFrame.screenContentGeometry(in: renderSize, crop: crop)

    // 导出侧的几何（makeScreenPlacementGeometry）
    let exportGeometry = makeScreenPlacementGeometry(
        sourceSize: sourceSize,
        screenFrame: screenFrame,
        crop: crop,
        renderSize: renderSize
    )

    // visibleRect 和 fullRect 必须完全一致（浮点误差允许 0.01 像素）
    expectClose(exportGeometry.visibleRect.minX, previewGeometry.visibleRect.minX, tolerance: 0.01)
    expectClose(exportGeometry.visibleRect.minY, previewGeometry.visibleRect.minY, tolerance: 0.01)
    expectClose(exportGeometry.visibleRect.width, previewGeometry.visibleRect.width, tolerance: 0.01)
    expectClose(exportGeometry.visibleRect.height, previewGeometry.visibleRect.height, tolerance: 0.01)

    expectClose(exportGeometry.fullRect.minX, previewGeometry.fullRect.minX, tolerance: 0.01)
    expectClose(exportGeometry.fullRect.minY, previewGeometry.fullRect.minY, tolerance: 0.01)
    expectClose(exportGeometry.fullRect.width, previewGeometry.fullRect.width, tolerance: 0.01)
    expectClose(exportGeometry.fullRect.height, previewGeometry.fullRect.height, tolerance: 0.01)
}

@Test("项目默认生成三个平台变体")
func recordingProjectBootstrapsPlatformVariants() {
    let project = RecordingProject.newProject(name: "Demo Session")

    #expect(project.variants.count == 3)
    #expect(project.variants.map(\.platform).contains(.xiaohongshu))
    #expect(project.variants.map(\.platform).contains(.douyin))
    #expect(project.variants.map(\.platform).contains(.bilibili))
}

@Test("导出表单只导出启用平台")
func exportSelectionOnlyIncludesEnabledVariants() {
    let variants = [
        PlatformVariant(template: .xiaohongshu),
        PlatformVariant(template: .douyin),
        PlatformVariant(template: .bilibili),
    ]
    var selection = ExportSelection(variants: variants)
    selection.toggle(.douyin)

    let enabled = selection.enabledVariants.map(\.platform)
    #expect(enabled == [.xiaohongshu, .bilibili])
}

@Test("区域选择会被归一化为正向矩形")
func captureRegionNormalizesDragDirection() {
    let region = CaptureRegion(from: .init(x: 420, y: 320), to: .init(x: 120, y: 140))

    #expect(region.origin == .init(x: 120, y: 140))
    #expect(region.size == .init(width: 300, height: 180))
}

@Test("区域选择会限制最小尺寸")
func captureRegionClampsToMinimumSize() {
    let region = CaptureRegion(from: .init(x: 100, y: 120), to: .init(x: 118, y: 132), minimumSize: .init(width: 160, height: 120))

    #expect(region.size.width == 160)
    #expect(region.size.height == 120)
}

@Test("区域选择会被限制在画布范围内")
func captureRegionClampsToCanvasBounds() {
    let region = CaptureRegion(origin: .init(x: 640, y: 420), size: .init(width: 240, height: 180))
    let clamped = region.clamped(to: .init(width: 720, height: 520))

    #expect(clamped.origin == .init(x: 480, y: 340))
    #expect(clamped.size == .init(width: 240, height: 180))
}

@Test("相机浮层默认落在录制区域内部")
func cameraOverlayDefaultsInsideCaptureRegion() {
    let region = CaptureRegion(origin: .init(x: 100, y: 80), size: .init(width: 500, height: 320))
    let overlay = CameraOverlayLayout.default(in: region)

    #expect(overlay.style.shape == .roundedCard)
    #expect(overlay.origin.x >= region.origin.x)
    #expect(overlay.origin.y >= region.origin.y)
    #expect(overlay.origin.x + overlay.size.width <= region.maxX)
    #expect(overlay.origin.y + overlay.size.height <= region.maxY)
}

@Test("相机浮层会被限制在录制区域内")
func cameraOverlayClampsToCaptureRegionBounds() {
    let region = CaptureRegion(origin: .init(x: 80, y: 50), size: .init(width: 320, height: 240))
    let overlay = CameraOverlayLayout(
        origin: .init(x: 340, y: 260),
        size: .init(width: 120, height: 120),
        style: .creatorDefault
    )
    let clamped = overlay.clamped(to: region)

    #expect(clamped.origin == .init(x: 262, y: 152))
    #expect(clamped.size == .init(width: 120, height: 120))
}

@Test("相机浮层缩放会限制最小尺寸")
func cameraOverlayResizeClampsToMinimumSize() {
    let region = CaptureRegion(origin: .init(x: 80, y: 50), size: .init(width: 320, height: 240))
    let overlay = CameraOverlayLayout.default(in: region)
    let resized = overlay.resized(by: .init(width: -200, height: -200), in: region)

    #expect(resized.size == .init(width: 72, height: 72))
    #expect(resized.origin.x + resized.size.width <= region.maxX)
    #expect(resized.origin.y + resized.size.height <= region.maxY)
}

@Test("相机浮层缩放会限制最大尺寸")
func cameraOverlayResizeClampsToMaximumSize() {
    let region = CaptureRegion(origin: .init(x: 40, y: 40), size: .init(width: 260, height: 220))
    let overlay = CameraOverlayLayout(origin: .init(x: 160, y: 120), size: .init(width: 100, height: 100), style: .creatorDefault)
    let resized = overlay.resized(by: .init(width: 220, height: 220), in: region)

    #expect(resized.size == .init(width: 122, height: 122))
    #expect(resized.origin == .init(x: 160, y: 120))
}

@Test("录屏配置会继承当前选区和 overlay 状态")
@MainActor
func captureSessionConfigurationUsesCurrentAppState() {
    let viewModel = AppViewModel()
    let region = CaptureRegion(origin: .init(x: 120, y: 90), size: .init(width: 640, height: 360))
    let camera = CameraOverlayLayout(
        origin: .init(x: 560, y: 260),
        size: .init(width: 120, height: 120),
        style: CameraStyle(shape: .circle, shadow: 0.18, borderOpacity: 0.22, blurEnabled: true)
    )
    let displays = [
        DisplaySource(id: 1, name: "Main Display", frame: .init(x: 0, y: 0, width: 1728, height: 1117), isPrimary: true),
        DisplaySource(id: 2, name: "Studio Display", frame: .init(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false),
    ]

    viewModel.updateAvailableDisplays(displays)
    viewModel.select(displayID: 2)
    viewModel.updateCaptureRegion(region, canvasSize: .init(width: 1280, height: 720))
    viewModel.updateCameraOverlay(camera)
    viewModel.toggleMicrophone()

    let configuration = viewModel.makeCaptureSessionConfiguration()

    #expect(configuration.region == region)
    #expect(configuration.display.id == 2)
    #expect(configuration.cameraOverlay?.style.shape == .circle)
    #expect(configuration.microphoneEnabled)
    #expect(!configuration.systemAudioEnabled)
}

@Test("显示器变更后会回退到有效选择")
@MainActor
func appViewModelFallsBackToAvailableDisplaySelection() {
    let viewModel = AppViewModel()
    let displays = [
        DisplaySource(id: 1, name: "Main Display", frame: .init(x: 0, y: 0, width: 1728, height: 1117), isPrimary: true),
        DisplaySource(id: 2, name: "Studio Display", frame: .init(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false),
    ]

    viewModel.updateAvailableDisplays(displays)
    viewModel.select(displayID: 2)
    viewModel.updateAvailableDisplays([displays[0]])

    #expect(viewModel.selectedDisplaySource.id == 1)
}

@Test("启动时会加载真实显示器列表")
@MainActor
func appViewModelLoadsAvailableDisplaysOnBootstrap() async {
    let captureService = FakeScreenCaptureService(
        availableDisplaysResult: [
            DisplaySource(id: 5, name: "Built-in Display", frame: .init(x: 0, y: 0, width: 1512, height: 982), isPrimary: true),
            DisplaySource(id: 8, name: "Studio Display", frame: .init(x: 1512, y: 0, width: 2560, height: 1440), isPrimary: false),
        ],
        recordingResult: nil
    )
    let viewModel = AppViewModel(captureService: captureService, exportService: FakePlatformExportService(results: []))

    await viewModel.bootstrap()

    #expect(await captureService.availableDisplaysCallCount == 1)
    #expect(viewModel.availableDisplays.map(\.id) == [5, 8])
    #expect(viewModel.selectedDisplaySource.id == 5)
}

@Test("录屏配置会映射到选中显示器坐标")
@MainActor
func captureSessionConfigurationMapsToSelectedDisplayFrame() {
    let viewModel = AppViewModel()
    let displays = [
        DisplaySource(id: 1, name: "Main Display", frame: .init(x: 0, y: 0, width: 1512, height: 982), isPrimary: true),
        DisplaySource(id: 2, name: "Studio Display", frame: .init(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false),
    ]

    viewModel.updateAvailableDisplays(displays)
    viewModel.select(displayID: 2)
    viewModel.updateCaptureRegion(
        CaptureRegion(origin: .init(x: 160, y: 90), size: .init(width: 640, height: 360)),
        canvasSize: .init(width: 1280, height: 720)
    )

    let configuration = viewModel.makeCaptureSessionConfiguration()

    #expect(configuration.displaySourceRect == .init(x: 2160, y: 135, width: 960, height: 540))
}

@Test("桌面坐标选区会映射为当前显示器内的归一化区域")
func captureSessionConfigurationMapsScreenSelectionIntoDisplayRegion() {
    let display = DisplaySource(id: 2, name: "Studio Display", frame: .init(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false)
    let configuration = CaptureSessionConfiguration.fromScreenSelection(
        CGRect(x: 2160, y: 135, width: 960, height: 540),
        on: display,
        cameraOverlay: nil,
        microphoneEnabled: true,
        systemAudioEnabled: false
    )

    #expect(configuration.region == .init(origin: .init(x: 240, y: 135), size: .init(width: 960, height: 540)))
    #expect(configuration.canvasSize == .init(width: 1920, height: 1080))
    #expect(configuration.displaySourceRect == .init(x: 2160, y: 135, width: 960, height: 540))
}

@Test("窗口坐标转换会使用所属显示器而不是主屏高度")
func windowFrameConversionUsesOwningDisplayBounds() {
    let display = DisplaySource(id: 2, name: "Studio Display", frame: .init(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false)
    let converted = convertWindowFrameFromScreenCaptureKit(
        CGRect(x: 2200, y: 140, width: 640, height: 360),
        on: display
    )

    #expect(converted == CGRect(x: 2200, y: 580, width: 640, height: 360))
}

@Test("桌面坐标选区会被限制在当前显示器内")
func captureSessionConfigurationClampsScreenSelectionToDisplayBounds() {
    let display = DisplaySource(id: 1, name: "Main Display", frame: .init(x: 0, y: 0, width: 1512, height: 982), isPrimary: true)
    let configuration = CaptureSessionConfiguration.fromScreenSelection(
        CGRect(x: -120, y: 40, width: 900, height: 1200),
        on: display,
        cameraOverlay: nil,
        microphoneEnabled: false,
        systemAudioEnabled: false
    )

    #expect(configuration.region == .init(origin: .init(x: 0, y: 40), size: .init(width: 780, height: 942)))
    #expect(configuration.displaySourceRect == .init(x: 0, y: 40, width: 781, height: 942))
}

@Test("悬浮条会在靠近屏幕边缘时自动吸附")
func floatingPanelPlacementSnapsToVisibleFrameEdges() {
    let visibleFrame = CGRect(x: 20, y: 40, width: 1440, height: 900)
    let origin = FloatingPanelPlacement.snappedOrigin(
        proposedOrigin: CGPoint(x: 28, y: 52),
        panelSize: .init(width: 372, height: 112),
        visibleFrame: visibleFrame,
        snapDistance: 24
    )

    #expect(origin == CGPoint(x: 20, y: 40))
}

@Test("悬浮条恢复位置时会回到可见区域")
func floatingPanelPlacementRestoresOffscreenOriginIntoVisibleFrame() {
    let visibleFrame = CGRect(x: 100, y: 80, width: 1280, height: 720)
    let origin = FloatingPanelPlacement.restoredOrigin(
        storedOrigin: CGPoint(x: 1600, y: -120),
        panelSize: .init(width: 372, height: 112),
        visibleFrame: visibleFrame
    )

    #expect(origin == CGPoint(x: 1008, y: 80))
}

@Test("悬浮条恢复位置时会忽略非法坐标")
func floatingPanelPlacementFallsBackWhenStoredOriginIsNonFinite() {
    let visibleFrame = CGRect(x: 100, y: 80, width: 1280, height: 720)
    let origin = FloatingPanelPlacement.restoredOrigin(
        storedOrigin: CGPoint(x: CGFloat.nan, y: CGFloat.infinity),
        panelSize: .init(width: 372, height: 112),
        visibleFrame: visibleFrame
    )

    #expect(origin == CGPoint(x: 100, y: 80))
}

@Test("悬浮条恢复位置时会忽略非法可见区域")
func floatingPanelPlacementFallsBackWhenVisibleFrameIsNonFinite() {
    let origin = FloatingPanelPlacement.restoredOrigin(
        storedOrigin: CGPoint(x: 320, y: 160),
        panelSize: .init(width: 372, height: 112),
        visibleFrame: CGRect(x: CGFloat.nan, y: CGFloat.infinity, width: 1280, height: 720)
    )

    #expect(origin == .zero)
}

@Test("悬浮条恢复位置时会忽略非法窗口尺寸")
func floatingPanelPlacementFallsBackWhenPanelSizeIsNonFinite() {
    let visibleFrame = CGRect(x: 100, y: 80, width: 1280, height: 720)
    let origin = FloatingPanelPlacement.restoredOrigin(
        storedOrigin: CGPoint(x: 420, y: 220),
        panelSize: .init(width: CGFloat.nan, height: CGFloat.infinity),
        visibleFrame: visibleFrame
    )

    #expect(origin == CGPoint(x: 100, y: 80))
}

@Test("录制开始时会隐藏原本可见的 Studio 并在结束后恢复")
func studioWindowVisibilityStateRestoresStudioAfterRecordingEnds() {
    var state = StudioWindowVisibilityState()

    #expect(state.recordingDidStart(studioIsVisible: true) == .hide)
    #expect(state.recordingDidEnd() == .show)
}

@Test("录制前未打开 Studio 时结束录制不会额外弹窗")
func studioWindowVisibilityStateKeepsStudioHiddenWhenItWasNotVisible() {
    var state = StudioWindowVisibilityState()

    #expect(state.recordingDidStart(studioIsVisible: false) == .none)
    #expect(state.recordingDidEnd() == .none)
}

@Test("桌面选区 overlay 失活时会取消选择")
func desktopRegionPickerSessionCancelsWhenOverlayBecomesInactive() {
    var session = DesktopRegionPickerSession()

    #expect(session.begin() == true)
    #expect(session.overlayDidResignActive() == .cancel)
    #expect(session.overlayDidResignActive() == .none)
}

@Test("桌面选区需要可交互的 overlay 窗口配置")
func desktopRegionPickerConfigurationRequiresInteractiveOverlay() {
    let configuration = DesktopRegionPickerConfiguration.interactiveOverlay

    #expect(configuration.activatesApp)
    #expect(configuration.canBecomeKey)
    #expect(configuration.cancelsOnEscape)
}

@Test("开始录制会切换为录制状态")
@MainActor
func appViewModelStartsRecordingState() {
    let viewModel = AppViewModel()

    viewModel.startRecordingSession()

    #expect(viewModel.phase == .recording)
    #expect(viewModel.recordingState == .recording)
}

@Test("未录制时不能手动切到录制页")
@MainActor
func appViewModelPreventsManualRecordingScreenSelectionWhenIdle() {
    let viewModel = AppViewModel()

    viewModel.transitionToPhase(.recording)

    #expect(viewModel.phase == .preparation)
}

@Test("录制时会锁定 setup 入口")
@MainActor
func appViewModelDisablesSetupEntryWhileRecording() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))

    #expect(viewModel.canAdjustCaptureSetup)

    viewModel.startRecordingSession()

    #expect(!viewModel.canAdjustCaptureSetup)
}

@Test("录制时不能切离录制页")
@MainActor
func appViewModelPreventsLeavingRecordingScreenWhileActive() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))

    viewModel.startRecordingSession()
    viewModel.transitionToPhase(.editing)

    #expect(viewModel.phase == .recording)
}

@Test("重复开始录制不会重新触发录制状态")
@MainActor
func appViewModelIgnoresDuplicateRecordingStarts() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))

    viewModel.startRecordingSession()
    viewModel.startRecordingSession()

    #expect(viewModel.phase == .recording)
    #expect(viewModel.recordingState == .recording)
}

@Test("悬浮控制条会反映当前录制状态")
@MainActor
func appViewModelProvidesFloatingControlCopy() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
    viewModel.updateAvailableDisplays([
        DisplaySource(id: 1, name: "Main Display", frame: .init(x: 0, y: 0, width: 1728, height: 1117), isPrimary: true),
    ])
    viewModel.updateCaptureRegion(.init(origin: .init(x: 100, y: 80), size: .init(width: 720, height: 405)), canvasSize: .init(width: 1728, height: 1117))

    #expect(viewModel.floatingControlTitle == "Ready to Capture")
    #expect(viewModel.floatingControlSubtitle == "Main Display · 720 × 405")
    #expect(viewModel.floatingPrimaryActionTitle == "Record")

    viewModel.startRecordingSession()

    #expect(viewModel.floatingControlTitle == "Recording")
    #expect(viewModel.floatingPrimaryActionTitle == "Stop")
}

@Test("停止录制后会回到编辑态但悬浮条恢复可录制")
@MainActor
func appViewModelReturnsFloatingControlToIdleAfterStop() async {
    let captureService = FakeScreenCaptureService(recordingResult: .init(
        fileURL: URL(fileURLWithPath: "/tmp/capture.mp4"),
        durationSeconds: 8,
        fileSizeBytes: 4_096
    ))
    let viewModel = AppViewModel(captureService: captureService, exportService: FakePlatformExportService(results: []))

    viewModel.startRecordingSession()
    await viewModel.stopRecordingSession()

    #expect(viewModel.phase == .completion)
    #expect(viewModel.floatingControlTitle == "Ready to Capture")
    #expect(viewModel.floatingPrimaryActionTitle == "Record")
}

@Test("Studio 可返回录制准备并清理编辑态")
@MainActor
func appViewModelStartNewRecordingResetsEditingState() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
    viewModel.latestRecording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/editing-capture.mp4"),
        durationSeconds: 8,
        fileSizeBytes: 4_096
    )
    viewModel.exportState = .completed([
        ExportedVariantResult(
            platform: .douyin,
            fileURL: URL(fileURLWithPath: "/tmp/douyin.mp4"),
            renderSize: .init(width: 1080, height: 1920),
            fileSizeBytes: 16_000_000
        )
    ])
    viewModel.sourceExportState = .completed([
        ExportedSourceAsset(kind: .screen, fileURL: URL(fileURLWithPath: "/tmp/screen.mp4"), fileSizeBytes: 32_000_000)
    ])
    viewModel.playbackState = .playing
    viewModel.playbackPositionSeconds = 5
    viewModel.trimStartSeconds = 1
    viewModel.trimEndSeconds = 4
    viewModel.exportSheetPresented = true
    viewModel.openInStudio()

    viewModel.startNewRecording()

    #expect(viewModel.phase == .preparation)
    #expect(viewModel.latestRecording == nil)
    #expect(viewModel.exportState == .idle)
    #expect(viewModel.sourceExportState == .idle)
    #expect(viewModel.playbackState == .paused)
    #expect(viewModel.playbackPositionSeconds == 0)
    #expect(viewModel.trimStartSeconds == 0)
    #expect(viewModel.trimEndSeconds == nil)
    #expect(viewModel.exportSheetPresented == false)
}

@Test("ViewModel 会应用真实桌面选区结果")
@MainActor
func appViewModelAppliesScreenSelectionToCaptureRegion() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
    let display = DisplaySource(id: 2, name: "Studio Display", frame: .init(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false)
    viewModel.updateAvailableDisplays([display])
    viewModel.select(displayID: 2)

    viewModel.applyScreenSelection(.init(x: 2160, y: 135, width: 960, height: 540))

    #expect(viewModel.captureCanvasSize == .init(width: 1920, height: 1080))
    #expect(viewModel.captureRegion == .init(origin: .init(x: 240, y: 135), size: .init(width: 960, height: 540)))
}

@Test("流描述会映射选区和音频开关")
func screenStreamDescriptorMapsCaptureConfiguration() {
    let configuration = CaptureSessionConfiguration(
        display: .init(id: 7, name: "Studio Display", frame: .init(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false),
        region: .init(origin: .init(x: 160, y: 90), size: .init(width: 640, height: 360)),
        canvasSize: .init(width: 1280, height: 720),
        cameraOverlay: nil,
        microphoneEnabled: true,
        systemAudioEnabled: true
    )

    let descriptor = ScreenStreamDescriptor(configuration: configuration, pointPixelScale: 2)

    #expect(descriptor.displayID == 7)
    #expect(descriptor.sourceRect == .init(x: 240, y: 135, width: 960, height: 540))
    #expect(descriptor.outputSize == .init(width: 1920, height: 1080))
    #expect(descriptor.capturesAudio)
    #expect(descriptor.captureMicrophone)
    #expect(descriptor.showsCursor)
}

@Test("录屏服务会启动并停止底层采集会话")
func screenCaptureServiceStartsAndStopsUnderlyingSession() async throws {
    let session = FakeCaptureSession()
    let builder = FakeCaptureSessionBuilder(session: session)
    let service = ScreenCaptureService(sessionBuilder: builder)
    let configuration = CaptureSessionConfiguration(
        display: .init(id: 1, name: "Main Display", frame: .init(x: 0, y: 0, width: 1728, height: 1117), isPrimary: true),
        region: .defaultSelection,
        canvasSize: .init(width: 1280, height: 720),
        cameraOverlay: nil,
        microphoneEnabled: false,
        systemAudioEnabled: false
    )

    try await service.start(configuration: configuration)
    _ = await service.stop()

    #expect(await builder.makeSessionCallCount == 1)
    #expect(await builder.lastConfiguration == configuration)
    #expect(await session.startCallCount == 1)
    #expect(await session.stopCallCount == 1)
}

@Test("重复开始录制不会重复创建底层采集会话")
func screenCaptureServiceIgnoresDuplicateStarts() async throws {
    let session = FakeCaptureSession()
    let builder = FakeCaptureSessionBuilder(session: session)
    let service = ScreenCaptureService(sessionBuilder: builder)
    let configuration = CaptureSessionConfiguration(
        display: .init(id: 1, name: "Main Display", frame: .init(x: 0, y: 0, width: 1728, height: 1117), isPrimary: true),
        region: .defaultSelection,
        canvasSize: .init(width: 1280, height: 720),
        cameraOverlay: nil,
        microphoneEnabled: false,
        systemAudioEnabled: false
    )

    try await service.start(configuration: configuration)
    try await service.start(configuration: configuration)

    #expect(await builder.makeSessionCallCount == 1)
    #expect(await session.startCallCount == 1)
}

@Test("录屏服务停止时会返回录制文件结果")
func screenCaptureServiceReturnsRecordingResultOnStop() async throws {
    let session = FakeCaptureSession(recordingResult: .init(
        fileURL: URL(fileURLWithPath: "/tmp/session.mp4"),
        durationSeconds: 12.4,
        fileSizeBytes: 2_048
    ))
    let builder = FakeCaptureSessionBuilder(session: session)
    let service = ScreenCaptureService(sessionBuilder: builder)
    let configuration = CaptureSessionConfiguration(
        display: .init(id: 1, name: "Main Display", frame: .init(x: 0, y: 0, width: 1728, height: 1117), isPrimary: true),
        region: .defaultSelection,
        canvasSize: .init(width: 1280, height: 720),
        cameraOverlay: nil,
        microphoneEnabled: false,
        systemAudioEnabled: true
    )

    try await service.start(configuration: configuration)
    let result = await service.stop()

    #expect(result?.fileURL.lastPathComponent == "session.mp4")
    #expect(result?.durationSeconds == 12.4)
    #expect(result?.fileSizeBytes == 2_048)
}

@Test("ViewModel 停止录制后会保存最近一次录制结果")
@MainActor
func appViewModelStoresLatestRecordingResult() async {
    let captureService = FakeScreenCaptureService(recordingResult: .init(
        fileURL: URL(fileURLWithPath: "/tmp/capture.mp4"),
        durationSeconds: 8,
        fileSizeBytes: 4_096
    ))
    let viewModel = AppViewModel(captureService: captureService)

    viewModel.startRecordingSession()
    await viewModel.stopRecordingSession()

    #expect(viewModel.phase == .completion)
    #expect(viewModel.latestRecording?.fileURL.lastPathComponent == "capture.mp4")
}

@Test("录制结果可根据文件是否存在判断是否可预览")
func recordingResultDetectsPreviewAvailability() throws {
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("preview-test-\(UUID().uuidString).mp4")
    let result = RecordingResult(fileURL: fileURL, durationSeconds: 3, fileSizeBytes: 128)

    #expect(!result.isPreviewAvailable)

    try Data([0x00]).write(to: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    #expect(result.isPreviewAvailable)
}

@Test("平台预览会生成居中的竖屏裁切框")
func platformPreviewCropUsesCenteredPortraitWindow() {
    let crop = PlatformPreviewCrop(videoSize: .init(width: 1920, height: 1080), platform: .douyin)

    #expect(crop.aspectRatio == 9.0 / 16.0)
    #expect(crop.cropRect == CGRect(x: 656.25, y: 0, width: 607.5, height: 1080))
}

@Test("平台预览在匹配比例时保持全画面")
func platformPreviewCropKeepsFullFrameWhenAspectAlreadyMatches() {
    let crop = PlatformPreviewCrop(videoSize: .init(width: 1920, height: 1080), platform: .bilibili)

    #expect(crop.cropRect == CGRect(x: 0, y: 0, width: 1920, height: 1080))
}

@Test("平台会提供标准导出分辨率")
func platformKindProvidesStandardExportRenderSizes() {
    #expect(PlatformKind.xiaohongshu.exportRenderSize == .init(width: 1080, height: 1440))
    #expect(PlatformKind.douyin.exportRenderSize == .init(width: 1080, height: 1920))
    #expect(PlatformKind.bilibili.exportRenderSize == .init(width: 1920, height: 1080))
}

@Test("导出校验会接受匹配的平台尺寸与时长")
func exportedVariantValidationAcceptsMatchingMetadata() {
    let metadata = ExportedVideoMetadata(renderSize: .init(width: 1080, height: 1920), durationSeconds: 11.8)

    #expect(PlatformExportValidator.validate(metadata: metadata, for: .douyin, sourceDurationSeconds: 12) == nil)
}

@Test("导出校验会拒绝错误的平台尺寸")
func exportedVariantValidationRejectsUnexpectedRenderSize() {
    let metadata = ExportedVideoMetadata(renderSize: .init(width: 1280, height: 720), durationSeconds: 11.8)

    let error = PlatformExportValidator.validate(metadata: metadata, for: .douyin, sourceDurationSeconds: 12)
    #expect(error == .invalidRenderSize(expected: .init(width: 1080, height: 1920), actual: .init(width: 1280, height: 720)))
}

@Test("导出校验会拒绝异常缩短的时长")
func exportedVariantValidationRejectsDurationRegression() {
    let metadata = ExportedVideoMetadata(renderSize: .init(width: 1080, height: 1920), durationSeconds: 2)

    let error = PlatformExportValidator.validate(metadata: metadata, for: .douyin, sourceDurationSeconds: 12)
    #expect(error == .invalidDuration(expectedMinimum: 11.4, actual: 2.0))
}

@Test("画布裁剪几何会保持与 Studio 一致的完整视频区域")
func canvasScreenContentGeometryMatchesStudioCropModel() {
let frame = CanvasElementFrame(centerX: 0.5, centerY: 0.5, widthRatio: 0.6, heightRatio: 0.4)
let crop = ScreenCropRect(minX: 0.1, minY: 0.2, width: 0.5, height: 0.5)

let geometry = frame.screenContentGeometry(in: .init(width: 1000, height: 2000), crop: crop)

#expect(geometry.visibleRect == CGRect(x: 200, y: 600, width: 600, height: 800))
#expect(geometry.fullRect == CGRect(x: 80, y: 280, width: 1200, height: 1600))
}

@Test("点击触发 auto-zoom 会生成单个镜头段")
func clickTriggeredAutoZoomBuildsSingleSegment() {
let settings = SmartAutoZoomSettings(
    isEnabled: true,
    zoomScale: 2,
    leadInSeconds: 0.2,
    holdSeconds: 0.6,
    releaseSeconds: 0.3,
    mergeGapSeconds: 0.15
)
let segments = makeClickTriggeredAutoZoomSegments(
    clicks: [SmartAutoZoomClickEvent(timestampSeconds: 1.0, normalizedX: 0.75, normalizedY: 0.25)],
    durationSeconds: 5,
    settings: settings
)

#expect(segments.count == 1)
expectClose(segments[0].startSeconds, 0.8)
expectClose(segments[0].focusSeconds, 1.0)
expectClose(segments[0].holdEndSeconds, 1.6)
expectClose(segments[0].endSeconds, 1.9)
expectClose(segments[0].normalizedX, 0.75)
expectClose(segments[0].normalizedY, 0.25)
}

@Test("连续近距离点击会合并为一个 auto-zoom 镜头段")
func clickTriggeredAutoZoomMergesNearbyClicks() {
let settings = SmartAutoZoomSettings(
    isEnabled: true,
    zoomScale: 2,
    leadInSeconds: 0.2,
    holdSeconds: 0.6,
    releaseSeconds: 0.3,
    mergeGapSeconds: 0.15
)
let segments = makeClickTriggeredAutoZoomSegments(
    clicks: [
        SmartAutoZoomClickEvent(timestampSeconds: 1.0, normalizedX: 0.25, normalizedY: 0.4),
        SmartAutoZoomClickEvent(timestampSeconds: 1.7, normalizedX: 0.7, normalizedY: 0.6)
    ],
    durationSeconds: 5,
    settings: settings
)

#expect(segments.count == 1)
expectClose(segments[0].focusSeconds, 1.7)
expectClose(segments[0].holdEndSeconds, 2.3)
expectClose(segments[0].endSeconds, 2.6)
expectClose(segments[0].normalizedX, 0.7)
expectClose(segments[0].normalizedY, 0.6)
}

@Test("auto-zoom crop 会平滑进出并限制在边界内")
func clickTriggeredAutoZoomCropInterpolatesAndClampsToEdges() {
let settings = SmartAutoZoomSettings(
    isEnabled: true,
    zoomScale: 2,
    leadInSeconds: 0.2,
    holdSeconds: 0.6,
    releaseSeconds: 0.3,
    mergeGapSeconds: 0.15
)
let segments = makeClickTriggeredAutoZoomSegments(
    clicks: [SmartAutoZoomClickEvent(timestampSeconds: 1.0, normalizedX: 0.95, normalizedY: 0.05)],
    durationSeconds: 5,
    settings: settings
)

#expect(makeSmartAutoZoomCrop(at: 0.5, segments: segments) == .full)
#expect(makeSmartAutoZoomCrop(at: 1.0, segments: segments) == ScreenCropRect(minX: 0.5, minY: 0, width: 0.5, height: 0.5))
#expect(makeSmartAutoZoomCrop(at: 0.9, segments: segments) == ScreenCropRect(minX: 0.25, minY: 0, width: 0.75, height: 0.75))
#expect(makeSmartAutoZoomCrop(at: 2.7, segments: segments) == .full)
}

@Test("ViewModel 会把 auto-zoom 叠加到当前屏幕裁剪之上")
@MainActor
func appViewModelComposesPlaybackCropWithAutoZoom() {
let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
viewModel.latestRecording = RecordingResult(
    fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
    durationSeconds: 5,
    fileSizeBytes: 1_024,
    cursorClickEvents: [SmartAutoZoomClickEvent(timestampSeconds: 1.0, normalizedX: 0.5, normalizedY: 0.5)]
)
viewModel.smartAutoZoomSettings = SmartAutoZoomSettings(
    isEnabled: true,
    zoomScale: 2,
    leadInSeconds: 0.2,
    holdSeconds: 0.6,
    releaseSeconds: 0.3,
    mergeGapSeconds: 0.15
)
viewModel.updateCanvasScreenCrop(ScreenCropRect(minX: 0.1, minY: 0.2, width: 0.6, height: 0.6))
viewModel.updatePlaybackPosition(seconds: 1.0)

#expect(viewModel.currentPlaybackScreenCrop == ScreenCropRect(minX: 0.25, minY: 0.35, width: 0.3, height: 0.3))
}

@Test("ViewModel 支持按任意时间点计算 auto-zoom 预览裁剪")
@MainActor
func appViewModelBuildsPlaybackCropForArbitraryTime() {
let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
viewModel.latestRecording = RecordingResult(
    fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
    durationSeconds: 5,
    fileSizeBytes: 1_024,
    cursorClickEvents: [SmartAutoZoomClickEvent(timestampSeconds: 1.0, normalizedX: 0.5, normalizedY: 0.5)]
)
viewModel.smartAutoZoomSettings = SmartAutoZoomSettings(
    isEnabled: true,
    zoomScale: 2,
    leadInSeconds: 0.2,
    holdSeconds: 0.6,
    releaseSeconds: 0.3,
    mergeGapSeconds: 0.15
)
viewModel.updateCanvasScreenCrop(ScreenCropRect(minX: 0.1, minY: 0.2, width: 0.6, height: 0.6))

expectClose(
    viewModel.playbackScreenCrop(at: 0.9),
    ScreenCropRect(minX: 0.175, minY: 0.275, width: 0.45, height: 0.45)
)
}

@Test("启用 smart auto-zoom 时会暴露可调参数控件")
func smartAutoZoomControlModelsExposeEditableControls() {
    let controls = makeSmartAutoZoomControlModels(settings: SmartAutoZoomSettings(
        isEnabled: true,
        zoomScale: 2.4,
        leadInSeconds: 0.15,
        holdSeconds: 0.8,
        releaseSeconds: 0.35,
        mergeGapSeconds: 0.2
    ))

    #expect(controls.map(\.title) == ["放大倍数", "进入时长", "停留时长", "退出时长"])
    #expect(controls.map(\.formattedValue) == ["2.4x", "0.15s", "0.80s", "0.35s"])
}

@Test("关闭 smart auto-zoom 时不会暴露可调参数控件")
func smartAutoZoomControlModelsAreHiddenWhenDisabled() {
    let controls = makeSmartAutoZoomControlModels(settings: SmartAutoZoomSettings())

    #expect(controls.isEmpty)
}

@Test("渐变背景在导出端会使用翻转后的纵向坐标")
func canvasBackgroundUsesCoreAnimationGradientPoints() {

    let background = CanvasBackground.linearGradient(
        r1: 0.9, g1: 0.3, b1: 0.1,
        r2: 0.98, g2: 0.7, b2: 0.15,
        angle: 90
    )

    let swiftUI = try! #require(background.gradientPointsForSwiftUI())
    let coreAnimation = try! #require(background.gradientPointsForCoreAnimation())

    expectClose(swiftUI.start.x, 0.5)
    expectClose(swiftUI.start.y, 1.0)
    expectClose(swiftUI.end.x, 0.5)
    expectClose(swiftUI.end.y, 0.0)

    expectClose(coreAnimation.start.x, 0.5)
    expectClose(coreAnimation.start.y, 0.0)
    expectClose(coreAnimation.end.x, 0.5)
    expectClose(coreAnimation.end.y, 1.0)
}

@Test("没有录制文件时预览名保持 Pending")
@MainActor
func appViewModelPreviewNameFallsBackWhenNoRecordingExists() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))

    #expect(viewModel.currentPreviewFileURL == nil)
    #expect(viewModel.currentPreviewFileName == "Pending")
}

@Test("ViewModel 导出时只处理启用的平台")
@MainActor
func appViewModelExportsEnabledVariantsOnly() async {
    let exporter = FakePlatformExportService(results: [
        ExportedVariantResult(
            platform: .douyin,
            fileURL: URL(fileURLWithPath: "/tmp/douyin.mp4"),
            renderSize: .init(width: 1080, height: 1920),
            fileSizeBytes: 8_192
        )
    ])
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: exporter)
    viewModel.latestRecording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
        durationSeconds: 12,
        fileSizeBytes: 4_096
    )
    viewModel.toggleExportVariant(.xiaohongshu)
    viewModel.toggleExportVariant(.bilibili)
    viewModel.exportSheetPresented = true

    await viewModel.exportSelectedVariants()

    #expect(await exporter.exportCallCount == 1)
    #expect(await exporter.lastRecording?.fileURL.lastPathComponent == "source.mp4")
    #expect(await exporter.lastPlatforms == [.douyin])
    #expect(viewModel.exportSheetPresented == false)
    if case let .completed(results) = viewModel.exportState {
        #expect(results.count == 1)
        #expect(results.first?.platform == .douyin)
    } else {
        Issue.record("Expected exportState to become completed")
    }
}

@Test("ViewModel 导出时会透传 smart auto-zoom 设置")
@MainActor
func appViewModelPassesSmartAutoZoomSettingsToExporter() async {
    let exporter = FakePlatformExportService(results: [
        ExportedVariantResult(
            platform: .douyin,
            fileURL: URL(fileURLWithPath: "/tmp/douyin.mp4"),
            renderSize: .init(width: 1080, height: 1920),
            fileSizeBytes: 8_192
        )
    ])
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: exporter)
    viewModel.latestRecording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
        durationSeconds: 12,
        fileSizeBytes: 4_096,
        cursorClickEvents: [SmartAutoZoomClickEvent(timestampSeconds: 1.0, normalizedX: 0.5, normalizedY: 0.5)]
    )
    viewModel.smartAutoZoomSettings = SmartAutoZoomSettings(
        isEnabled: true,
        zoomScale: 2.45,
        leadInSeconds: 0.14,
        holdSeconds: 0.82,
        releaseSeconds: 0.34,
        mergeGapSeconds: 0.2
    )

    await viewModel.exportSelectedVariants()

    #expect(await exporter.lastSmartAutoZoomSettings == viewModel.smartAutoZoomSettings)
}

@Test("ViewModel 停止录制时会把点击事件写回结果")
@MainActor
func appViewModelPersistsRecordedCursorClicksOnStop() async {
    let recording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
        durationSeconds: 8,
        fileSizeBytes: 2_048
    )
    let captureService = FakeScreenCaptureService(recordingResult: recording)
    let viewModel = AppViewModel(captureService: captureService, exportService: FakePlatformExportService(results: []))
    let click = SmartAutoZoomClickEvent(timestampSeconds: 0.8, normalizedX: 0.42, normalizedY: 0.58)

    viewModel.startRecordingSession()
    viewModel.appendRecordedCursorClick(click)
    await viewModel.stopRecordingSession()

    #expect(viewModel.latestRecording?.cursorClickEvents == [click])
}

@Test("ViewModel 可以导出原素材文件")
@MainActor
func appViewModelExportsSourceAssets() async {
    let exporter = FakePlatformExportService(
        results: [],
        sourceAssets: [
            ExportedSourceAsset(
                kind: .screen,
                fileURL: URL(fileURLWithPath: "/tmp/source-screen.mp4"),
                fileSizeBytes: 20_480
            ),
            ExportedSourceAsset(
                kind: .camera,
                fileURL: URL(fileURLWithPath: "/tmp/source-camera.mp4"),
                fileSizeBytes: 10_240
            )
        ]
    )
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: exporter)
    viewModel.latestRecording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
        durationSeconds: 14,
        fileSizeBytes: 5_120,
        cameraFileURL: URL(fileURLWithPath: "/tmp/camera.mp4")
    )
    viewModel.exportSheetPresented = true

    await viewModel.exportSourceAssets()

    #expect(await exporter.sourceExportCallCount == 1)
    #expect(await exporter.lastSourceRecording?.cameraFileURL?.lastPathComponent == "camera.mp4")
    #expect(viewModel.exportSheetPresented == false)
    if case let .completed(results) = viewModel.sourceExportState {
        #expect(results.count == 2)
        #expect(results.map(\ .kind) == [.screen, .camera])
    } else {
        Issue.record("Expected sourceExportState to become completed")
    }
}

@Test("ViewModel 会优先使用当前平台的导出结果作为预览源")
@MainActor
func appViewModelPrefersExportedPreviewForSelectedPlatform() async {
    let exporter = FakePlatformExportService(results: [
        ExportedVariantResult(
            platform: .douyin,
            fileURL: URL(fileURLWithPath: "/tmp/douyin-export.mp4"),
            renderSize: .init(width: 1080, height: 1920),
            fileSizeBytes: 10_240
        )
    ])
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: exporter)
    viewModel.latestRecording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
        durationSeconds: 14,
        fileSizeBytes: 5_120
    )

    await viewModel.exportSelectedVariants()

    #expect(viewModel.currentPreviewFileURL?.lastPathComponent == "douyin-export.mp4")
    #expect(viewModel.currentPreviewFileName == "douyin-export.mp4")
}

@Test("ViewModel 在没有平台导出结果时回退到原始录制预览")
@MainActor
func appViewModelFallsBackToLatestRecordingPreview() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
    viewModel.latestRecording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
        durationSeconds: 9,
        fileSizeBytes: 2_048
    )
    viewModel.select(platform: .bilibili)

    #expect(viewModel.currentPreviewFileURL?.lastPathComponent == "source.mp4")
    #expect(viewModel.currentPreviewFileName == "source.mp4")
}

@Test("矩形 PiP 形状会立即套用横版默认比例")
@MainActor
func appViewModelRectanglePipShapeUsesRectangularDefaultAspect() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
    let original = try! #require(viewModel.currentCanvasLayout.pipFrame)

    viewModel.updateCanvasPipShape(.rectangle)

    let updated = try! #require(viewModel.currentCanvasLayout.pipFrame)
    let expectedHeight = original.widthRatio * Double(viewModel.selectedPlatform.aspectRatio) / (16.0 / 9.0)
    expectClose(updated.widthRatio, original.widthRatio)
    expectClose(updated.heightRatio, expectedHeight)
}

@Test("矩形 PiP 在切换平台时保留用户自定义宽高")
@MainActor
func appViewModelKeepsRectanglePipAspectWhenSelectingPlatform() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
    viewModel.updateCanvasPipShape(.rectangle)
    viewModel.updateCanvasPipFrame(.init(centerX: 0.78, centerY: 0.82, widthRatio: 0.32, heightRatio: 0.11))

    viewModel.select(platform: .douyin)

    let updated = try! #require(viewModel.currentCanvasLayout.pipFrame)
    expectClose(updated.widthRatio, 0.32)
    expectClose(updated.heightRatio, 0.11)
}

@Test("ViewModel 会维护播放状态切换")
@MainActor
func appViewModelTogglesPlaybackState() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))

    #expect(viewModel.playbackState == .paused)
    viewModel.togglePlayback()
    #expect(viewModel.playbackState == .playing)
    viewModel.togglePlayback()
    #expect(viewModel.playbackState == .paused)
    viewModel.restartPlayback()
    #expect(viewModel.playbackState == .playing)
}

@Test("播放结束后 ViewModel 会回到暂停态")
@MainActor
func appViewModelPausesWhenPlaybackFinishes() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
    viewModel.latestRecording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/demo.mp4"),
        durationSeconds: 12,
        fileSizeBytes: 1_024
    )
    viewModel.playbackState = .playing
    viewModel.playbackPositionSeconds = 4

    viewModel.handlePlaybackFinished()

    #expect(viewModel.playbackState == .paused)
    #expect(viewModel.playbackPositionSeconds == 12)
}

@Test("播完后再次点击播放会从头重播")
func playbackShouldRestartFromBeginningAfterFinish() {
    #expect(shouldRestartPlaybackFromBeginning(currentTime: 12, duration: 12))
    #expect(shouldRestartPlaybackFromBeginning(currentTime: 11.97, duration: 12))
    #expect(shouldRestartPlaybackFromBeginning(currentTime: 6, duration: 12) == false)
}

@Test("ViewModel 会根据总时长计算播放进度")
@MainActor
func appViewModelComputesPlaybackProgress() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
    viewModel.latestRecording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
        durationSeconds: 20,
        fileSizeBytes: 2_048
    )

    viewModel.updatePlaybackPosition(seconds: 5)

    #expect(viewModel.playbackProgress == 0.25)
    #expect(viewModel.currentPlaybackTimeLabel == "00:05")
    #expect(viewModel.totalPlaybackTimeLabel == "00:20")
}

@Test("ViewModel 拖动进度会更新播放时间")
@MainActor
func appViewModelSeeksPlaybackByProgress() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))
    viewModel.latestRecording = RecordingResult(
        fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
        durationSeconds: 40,
        fileSizeBytes: 2_048
    )

    viewModel.seekPlayback(toProgress: 0.5)

    #expect(viewModel.playbackPositionSeconds == 20)
    #expect(viewModel.playbackProgress == 0.5)
    #expect(viewModel.currentPlaybackTimeLabel == "00:20")
}

@Test("ViewModel 会格式化超过一分钟的播放时间")
@MainActor
func appViewModelFormatsPlaybackTimeLabels() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))

    #expect(viewModel.formatPlaybackTime(0) == "00:00")
    #expect(viewModel.formatPlaybackTime(65) == "01:05")
    #expect(viewModel.formatPlaybackTime(125) == "02:05")
}

private struct DouyinFrameComparisonContext {
    let referenceVideoURL: URL
    let candidateVideoURL: URL
}

private struct ImageDiffMetrics {
    let meanAbsoluteDiff: Double
    let diffRatio: Double
}

private enum ExportFrameComparisonError: Error {
    case imageDestinationUnavailable
    case imageWriteFailed
    case imageSourceUnavailable(URL)
    case imageDecodeFailed(URL)
    case imageSizeMismatch
}

private func makeDouyinFrameComparisonContext() throws -> DouyinFrameComparisonContext? {
    let exportsDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Reco", isDirectory: true)
        .appendingPathComponent("Exports", isDirectory: true)
    let referenceVideoURL = exportsDirectory.appendingPathComponent("douyin-51B7FB32-E4B2-4787-8060-485616C57FDA.mp4")
    guard FileManager.default.fileExists(atPath: referenceVideoURL.path) else {
        return nil
    }

    let candidates = try FileManager.default.contentsOfDirectory(
        at: exportsDirectory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    )
    .filter {
        $0.pathExtension == "mp4"
        && $0.lastPathComponent.hasPrefix("douyin-")
        && $0.lastPathComponent != referenceVideoURL.lastPathComponent
    }
    .sorted {
        let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return lhsDate > rhsDate
    }

    guard let candidateVideoURL = candidates.first else {
        return nil
    }

    return DouyinFrameComparisonContext(
        referenceVideoURL: referenceVideoURL,
        candidateVideoURL: candidateVideoURL
    )
}

private func writeDebugFramePNG(from videoURL: URL, stem: String, at seconds: Double = 0.5) async throws -> URL {
    let asset = AVURLAsset(url: videoURL)
    let duration = try await asset.load(.duration)
    let totalSeconds = max(CMTimeGetSeconds(duration), 0.1)
    let targetSeconds = min(seconds, max(totalSeconds - 0.1, 0))

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1080, height: 1920)

    let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)
    let (cgImage, _) = try await generator.image(at: time)

    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem).png")
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ExportFrameComparisonError.imageDestinationUnavailable
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ExportFrameComparisonError.imageWriteFailed
    }
    return outputURL
}

private func imageDiffMetrics(_ lhsURL: URL, _ rhsURL: URL) throws -> ImageDiffMetrics {
    let lhs = try loadCGImage(from: lhsURL)
    let rhs = try loadCGImage(from: rhsURL)
    guard lhs.width == rhs.width, lhs.height == rhs.height else {
        throw ExportFrameComparisonError.imageSizeMismatch
    }

    let lhsPixels = rgbaPixels(from: lhs)
    let rhsPixels = rgbaPixels(from: rhs)
    var diffPixels = 0
    var totalDifference: UInt64 = 0

    for index in stride(from: 0, to: lhsPixels.count, by: 4) {
        let redDiff = abs(Int(lhsPixels[index]) - Int(rhsPixels[index]))
        let greenDiff = abs(Int(lhsPixels[index + 1]) - Int(rhsPixels[index + 1]))
        let blueDiff = abs(Int(lhsPixels[index + 2]) - Int(rhsPixels[index + 2]))
        let pixelDifference = redDiff + greenDiff + blueDiff
        if pixelDifference > 24 {
            diffPixels += 1
        }
        totalDifference += UInt64(pixelDifference)
    }

    let totalPixels = lhs.width * lhs.height
    return ImageDiffMetrics(
        meanAbsoluteDiff: Double(totalDifference) / Double(totalPixels * 3),
        diffRatio: Double(diffPixels) / Double(totalPixels)
    )
}

private func loadCGImage(from url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw ExportFrameComparisonError.imageSourceUnavailable(url)
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ExportFrameComparisonError.imageDecodeFailed(url)
    }
    return image
}

private func rgbaPixels(from image: CGImage) -> [UInt8] {
    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
}

actor FakeCaptureSession: CaptureSessionRunning {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private let recordingResult: RecordingResult?

    init(recordingResult: RecordingResult? = nil) {
        self.recordingResult = recordingResult
    }

    func start() async throws {
        startCallCount += 1
    }

    func stop() async -> RecordingResult? {
        stopCallCount += 1
        return recordingResult
    }
}

actor FakeCaptureSessionBuilder: ScreenCaptureSessionBuilding {
    private(set) var makeSessionCallCount = 0
    private(set) var lastConfiguration: CaptureSessionConfiguration?
    let session: FakeCaptureSession

    init(session: FakeCaptureSession) {
        self.session = session
    }

    func makeSession(for configuration: CaptureSessionConfiguration) async throws -> any CaptureSessionRunning {
        makeSessionCallCount += 1
        lastConfiguration = configuration
        return session
    }
}

actor FakeScreenCaptureService: ScreenCaptureServicing {
    private(set) var availableDisplaysCallCount = 0
    let availableDisplaysResult: [DisplaySource]
    let recordingResult: RecordingResult?

    init(availableDisplaysResult: [DisplaySource] = [.placeholder], recordingResult: RecordingResult?) {
        self.availableDisplaysResult = availableDisplaysResult
        self.recordingResult = recordingResult
    }

    func availableDisplays() async throws -> [DisplaySource] {
        availableDisplaysCallCount += 1
        return availableDisplaysResult
    }

    func availableWindows() async throws -> [WindowSource] {
        []
    }

    func start(configuration: CaptureSessionConfiguration) async throws {
        _ = configuration
    }

    func stop() async -> RecordingResult? {
        recordingResult
    }
}

actor FakePlatformExportService: PlatformExportServicing {
    private(set) var exportCallCount = 0
    private(set) var sourceExportCallCount = 0
    private(set) var lastRecording: RecordingResult?
    private(set) var lastSourceRecording: RecordingResult?
    private(set) var lastPlatforms: [PlatformKind] = []
    private(set) var lastCanvasLayouts: [String: CanvasLayout] = [:]
    private(set) var lastSmartAutoZoomSettings = SmartAutoZoomSettings()
    let results: [ExportedVariantResult]
    let sourceAssets: [ExportedSourceAsset]

    init(results: [ExportedVariantResult], sourceAssets: [ExportedSourceAsset] = []) {
        self.results = results
        self.sourceAssets = sourceAssets
    }

    func export(
        recording: RecordingResult,
        variants: [PlatformVariant],
        trimStart: Double,
        trimEnd: Double?,
        canvasLayouts: [String: CanvasLayout],
        smartAutoZoomSettings: SmartAutoZoomSettings
    ) async throws -> [ExportedVariantResult] {
        _ = trimStart
        _ = trimEnd
        exportCallCount += 1
        lastRecording = recording
        lastPlatforms = variants.map(\.platform)
        lastCanvasLayouts = canvasLayouts
        lastSmartAutoZoomSettings = smartAutoZoomSettings
        return results
    }

    func exportSourceAssets(recording: RecordingResult) async throws -> [ExportedSourceAsset] {
        sourceExportCallCount += 1
        lastSourceRecording = recording
        return sourceAssets
    }
}
