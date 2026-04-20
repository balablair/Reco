import Foundation
import Testing
@testable import CreatorRecorderKit

@Test("平台变体从模板初始化")
func platformVariantUsesTemplateDefaults() {
    let template = ProjectTemplate.xiaohongshu
    let variant = PlatformVariant(template: template)

    #expect(variant.platform == .xiaohongshu)
    #expect(variant.aspectRatio == .portraitStory)
    #expect(variant.safeAreaPreset == .xiaohongshu)
    #expect(variant.cameraStyle.shape == .roundedCard)
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

    #expect(viewModel.currentScreen == .recording)
    #expect(viewModel.recordingState == .recording)
}

@Test("未录制时不能手动切到录制页")
@MainActor
func appViewModelPreventsManualRecordingScreenSelectionWhenIdle() {
    let viewModel = AppViewModel()

    viewModel.select(screen: .recording)

    #expect(viewModel.currentScreen == .preparation)
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
    viewModel.select(screen: .editor)

    #expect(viewModel.currentScreen == .recording)
}

@Test("重复开始录制不会重新触发录制状态")
@MainActor
func appViewModelIgnoresDuplicateRecordingStarts() {
    let viewModel = AppViewModel(captureService: FakeScreenCaptureService(recordingResult: nil), exportService: FakePlatformExportService(results: []))

    viewModel.startRecordingSession()
    viewModel.startRecordingSession()

    #expect(viewModel.currentScreen == .recording)
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

    #expect(viewModel.currentScreen == .editor)
    #expect(viewModel.floatingControlTitle == "Ready to Capture")
    #expect(viewModel.floatingPrimaryActionTitle == "Record")
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

    #expect(viewModel.currentScreen == AppViewModel.Screen.editor)
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

    func start(configuration: CaptureSessionConfiguration) async throws {
        _ = configuration
    }

    func stop() async -> RecordingResult? {
        recordingResult
    }
}

actor FakePlatformExportService: PlatformExportServicing {
    private(set) var exportCallCount = 0
    private(set) var lastRecording: RecordingResult?
    private(set) var lastPlatforms: [PlatformKind] = []
    let results: [ExportedVariantResult]

    init(results: [ExportedVariantResult]) {
        self.results = results
    }

    func export(recording: RecordingResult, variants: [PlatformVariant]) async throws -> [ExportedVariantResult] {
        exportCallCount += 1
        lastRecording = recording
        lastPlatforms = variants.map(\.platform)
        return results
    }
}
