import Foundation
import CoreGraphics
import Observation

// MARK: - 持久化快照结构

/// 持久化的用户偏好快照，只存不依赖运行时环境的设置。
/// 不包含录制状态、录制结果、播放位置等临时状态。
private struct AppUserPreferences: Codable {
    var selectedPlatform: PlatformKind
    var overlayState: OverlayState
    var smartAutoZoomSettings: SmartAutoZoomSettings
    var canvasLayouts: [String: CanvasLayout]
    var teleprompterText: String
    var teleprompterScrollSpeed: Double
    var cameraBeauty: CameraBeautySettings
}

// MARK: - 持久化存储

private enum AppStorage {
    static let preferencesKey = "CreatorRecorder.UserPreferences.v1"

    static func load() -> AppUserPreferences? {
        guard let data = UserDefaults.standard.data(forKey: preferencesKey) else { return nil }
        // 优先整体解码（无版本差异时最快）
        if let prefs = try? JSONDecoder().decode(AppUserPreferences.self, from: data) {
            return prefs
        }
        // 整体解码失败时（版本升级/字段增减），逐字段容错恢复
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
            guard let fieldData = try? JSONSerialization.data(withJSONObject: json[key] as Any) else { return nil }
            return try? decoder.decode(type, from: fieldData)
        }
        var defaults = AppUserPreferences(
            selectedPlatform: .douyin,
            overlayState: OverlayState(),
            smartAutoZoomSettings: SmartAutoZoomSettings(),
            canvasLayouts: [:],
            teleprompterText: "",
            teleprompterScrollSpeed: 40,
            cameraBeauty: .default
        )
        if let v = decode(PlatformKind.self,            key: "selectedPlatform")      { defaults.selectedPlatform = v }
        if let v = decode(OverlayState.self,            key: "overlayState")          { defaults.overlayState = v }
        if let v = decode(SmartAutoZoomSettings.self,   key: "smartAutoZoomSettings") { defaults.smartAutoZoomSettings = v }
        if let v = decode([String: CanvasLayout].self,  key: "canvasLayouts")         { defaults.canvasLayouts = v }
        if let v = json["teleprompterText"]      as? String { defaults.teleprompterText = v }
        if let v = json["teleprompterScrollSpeed"] as? Double { defaults.teleprompterScrollSpeed = v }
        if let v = decode(CameraBeautySettings.self,    key: "cameraBeauty")          { defaults.cameraBeauty = v }
        return defaults
    }

    static func save(_ prefs: AppUserPreferences) {
        guard let data = try? JSONEncoder().encode(prefs) else {
            NSLog("[AppStorage] save failed: encoding error")
            return
        }
        UserDefaults.standard.set(data, forKey: preferencesKey)
    }
}

@MainActor
@Observable
public final class AppViewModel {
    private let captureService: any ScreenCaptureServicing
    private let exportService: any PlatformExportServicing
    public var phase: AppPhase = .preparation
    public var project: RecordingProject = .newProject(name: "Creator Session")
    public var selectedPlatform: PlatformKind = .douyin
    public var exportSelection: ExportSelection
    public var exportSheetPresented = false
    public var inspectorPresented = true
    public var captureRegion: CaptureRegion
    public var cameraOverlay: CameraOverlayLayout
    public var overlayState = OverlayState()
    public var regionSelectionActive = false
    public var recordingState: RecordingState = .idle
    public var captureCanvasSize: CGSize = .init(width: 1280, height: 720)
    public var availableDisplays: [DisplaySource] = [.placeholder]
    public var selectedDisplayID: UInt32 = DisplaySource.placeholder.id
    /// 可用窗口列表（bootstrap 时加载）
    public var availableWindows: [WindowSource] = []
    /// 当前选择的捕获源（nil = 屏幕区域，非 nil = 特定窗口）
    public var selectedWindowSource: WindowSource? = nil
    public var latestRecording: RecordingResult?
    /// 录制期间摄像头独立录制生成的文件 URL（由外部 CameraRecorder 在 stop 前设置）
    public var pendingCameraFileURL: URL? = nil
    public var exportState: ExportState = .idle
    public var sourceExportState: SourceExportState = .idle
    public var playbackState: PlaybackState = .paused
    public var playbackPositionSeconds: Double = 0
    public var recordingElapsedSeconds: Int = 0
    /// 提词器文本
    public var teleprompterText: String = ""
    /// 提词器滚动速度（像素/秒），默认 40
    public var teleprompterScrollSpeed: Double = 40
    /// 裁剪起点（秒），0 = 不裁
    public var trimStartSeconds: Double = 0
    /// 裁剪终点（秒），nil = 用原始时长
    public var trimEndSeconds: Double? = nil
    /// 摄像头美颜 & 灯光设置
    public var cameraBeauty: CameraBeautySettings = .default
    /// click-triggered smart auto-zoom 的预览设置。
    public var smartAutoZoomSettings = SmartAutoZoomSettings()
    /// 各平台的画布布局（Studio 编辑器状态），key = PlatformKind.rawValue
    public var canvasLayouts: [String: CanvasLayout] = [:]
    @ObservationIgnored private var elapsedTimer: Timer?
    @ObservationIgnored private var recordedCursorClicks: [SmartAutoZoomClickEvent] = []
    /// 延迟保存的 task，防止高频操作时频繁写磁盘
    @ObservationIgnored private var saveDebounceTask: Task<Void, Never>? = nil

    public init(
        captureService: any ScreenCaptureServicing = ScreenCaptureService(),
        exportService: any PlatformExportServicing = PlatformExportService()
    ) {
        let project = RecordingProject.newProject(name: "Creator Session")
        self.captureService = captureService
        self.exportService = exportService
        self.project = project
        self.exportSelection = ExportSelection(variants: project.variants)
        self.captureRegion = .defaultSelection
        self.cameraOverlay = .default(in: .defaultSelection)

        // 初始化各平台默认画布布局（后面会被持久化数据覆盖）
        var layouts: [String: CanvasLayout] = [:]
        for platform in PlatformKind.allCases {
            layouts[platform.rawValue] = CanvasLayout.defaultLayout(for: platform, hasPiP: true)
        }
        self.canvasLayouts = layouts

        // 从磁盘恢复用户偏好
        if let saved = AppStorage.load() {
            self.selectedPlatform = saved.selectedPlatform
            self.overlayState = saved.overlayState
            self.smartAutoZoomSettings = saved.smartAutoZoomSettings
            self.teleprompterText = saved.teleprompterText
            self.teleprompterScrollSpeed = saved.teleprompterScrollSpeed
            self.cameraBeauty = saved.cameraBeauty
            // 将已保存的布局合并到默认布局中（缺失的平台用默认值补齐）
            for (key, layout) in saved.canvasLayouts {
                self.canvasLayouts[key] = layout
            }
        }
    }

    // MARK: - 持久化

    /// 将当前用户偏好异步写入磁盘（防抖 300ms，避免拖拽时频繁写入）
    public func savePreferences() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let prefs = AppUserPreferences(
                selectedPlatform: self.selectedPlatform,
                overlayState: self.overlayState,
                smartAutoZoomSettings: self.smartAutoZoomSettings,
                canvasLayouts: self.canvasLayouts,
                teleprompterText: self.teleprompterText,
                teleprompterScrollSpeed: self.teleprompterScrollSpeed,
                cameraBeauty: self.cameraBeauty
            )
            AppStorage.save(prefs)
        }
    }

    /// 获取当前选中平台的画布布局
    public var currentCanvasLayout: CanvasLayout {
        get { canvasLayouts[selectedPlatform.rawValue] ?? CanvasLayout.defaultLayout(for: selectedPlatform, hasPiP: overlayState.cameraVisible) }
        set { canvasLayouts[selectedPlatform.rawValue] = newValue }
    }

    public func updateCanvasBackground(_ background: CanvasBackground) {
        currentCanvasLayout.background = background
        savePreferences()
    }

    public func updateCanvasScreenFrame(_ frame: CanvasElementFrame) {
        currentCanvasLayout.screenFrame = frame
        savePreferences()
    }

    public func updateCanvasScreenCrop(_ crop: ScreenCropRect) {
        currentCanvasLayout.screenCrop = crop
        savePreferences()
    }

    public func updateCanvasPipFrame(_ frame: CanvasElementFrame?) {
        currentCanvasLayout.pipFrame = frame
        savePreferences()
    }

    public func updateCanvasPipShape(_ shape: CameraShape) {
        currentCanvasLayout.pipShape = shape
        currentCanvasLayout.normalizePipFrameForCurrentShape()
        savePreferences()
    }

    public func resetCanvasLayout() {
        currentCanvasLayout = CanvasLayout.defaultLayout(for: selectedPlatform, hasPiP: overlayState.cameraVisible)
        savePreferences()
    }

    public func transitionToPhase(_ newPhase: AppPhase) {
        // 录制进行中时，只允许停留在录制页，不允许切走
        guard !isRecordingActive || newPhase == .recording else { return }
        // 只有录制真正激活时才能进入录制页（防止手动跳转）
        if newPhase == .recording {
            guard isRecordingActive else { return }
        }
        phase = newPhase
    }

    public func select(platform: PlatformKind) {
        selectedPlatform = platform
        // 切换平台后，仅对圆形/方形类 PiP 重新校正像素正方形。
        if canvasLayouts[platform.rawValue]?.pipShape.usesSquarePixels == true {
            canvasLayouts[platform.rawValue]!.normalizePipFrameForCurrentShape()
        }
        savePreferences()
    }

    public var exportedVariantsByPlatform: [PlatformKind: ExportedVariantResult] {
        guard case let .completed(results) = exportState else { return [:] }
        return Dictionary(uniqueKeysWithValues: results.map { ($0.platform, $0) })
    }

    public var exportedSourceAssets: [ExportedSourceAsset] {
        guard case let .completed(results) = sourceExportState else { return [] }
        return results
    }

    public var currentPreviewFileURL: URL? {
        exportedVariantsByPlatform[selectedPlatform]?.fileURL ?? latestRecording?.fileURL
    }

    public var currentPreviewFileName: String {
        currentPreviewFileURL?.lastPathComponent ?? "Pending"
    }

    public var currentPlaybackScreenCrop: ScreenCropRect {
        playbackScreenCrop(at: playbackPositionSeconds)
    }

    public func playbackScreenCrop(at timeSeconds: Double) -> ScreenCropRect {
        playbackScreenCrop(baseCrop: currentCanvasLayout.screenCrop, at: timeSeconds)
    }

    public func playbackScreenCrop(baseCrop: ScreenCropRect, at timeSeconds: Double) -> ScreenCropRect {
        guard let recording = latestRecording else { return baseCrop }
        return makeComposedSmartAutoZoomCrop(
            baseCrop: baseCrop,
            at: timeSeconds,
            clicks: recording.cursorClickEvents,
            durationSeconds: recording.durationSeconds,
            settings: smartAutoZoomSettings
        )
    }

    public var playbackDurationSeconds: Double {
        latestRecording?.durationSeconds ?? 0
    }

    public var playbackProgress: Double {
        guard playbackDurationSeconds > 0 else { return 0 }
        return min(max(playbackPositionSeconds / playbackDurationSeconds, 0), 1)
    }

    public var currentPlaybackTimeLabel: String {
        formatPlaybackTime(playbackPositionSeconds)
    }

    public var totalPlaybackTimeLabel: String {
        formatPlaybackTime(playbackDurationSeconds)
    }

    public func select(displayID: UInt32) {
        guard availableDisplays.contains(where: { $0.id == displayID }) else { return }
        selectedDisplayID = displayID
    }

    public var selectedDisplaySource: DisplaySource {
        availableDisplays.first(where: { $0.id == selectedDisplayID })
        ?? availableDisplays.first
        ?? .placeholder
    }

    public var captureRegionLabel: String {
        "\(Int(captureRegion.size.width)) × \(Int(captureRegion.size.height))"
    }

    public var isRecordingActive: Bool {
        if case .recording = recordingState {
            return true
        }
        return false
    }

    public var floatingControlTitle: String {
        switch recordingState {
        case .idle:
            return "Ready to Capture"
        case .recording:
            return "Recording"
        case .failed:
            return "Capture Failed"
        }
    }

    public var floatingControlSubtitle: String {
        switch recordingState {
        case .failed(let message):
            return message
        case .idle, .recording:
            return "\(selectedDisplaySource.name) · \(captureRegionLabel)"
        }
    }

    public var floatingPrimaryActionTitle: String {
        isRecordingActive ? "Stop" : "Record"
    }

    public var canAdjustCaptureSetup: Bool {
        !isRecordingActive
    }

    public func updateAvailableDisplays(_ displays: [DisplaySource]) {
        let sanitized = displays.isEmpty ? [.placeholder] : displays
        availableDisplays = sanitized
        if !sanitized.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = (sanitized.first(where: \.isPrimary) ?? sanitized[0]).id
        }
    }

    public func bootstrap() async {
        do {
            let displays = try await captureService.availableDisplays()
            updateAvailableDisplays(displays)
            // 拿到真实屏幕尺寸后，把默认捕获区域设为全屏
            if let primary = displays.first(where: \.isPrimary) ?? displays.first {
                let fullScreen = CaptureRegion(origin: .zero, size: primary.frame.size)
                captureRegion  = fullScreen
                captureCanvasSize = primary.frame.size
                // 摄像头默认右下角 (距边 18pt, 约占宽 15%)
                cameraOverlay = defaultCameraOverlayForFullScreen(primary.frame.size)
            }
        } catch {
            updateAvailableDisplays([])
        }
        await refreshWindows()
    }

    /// 根据全屏尺寸计算右下角默认摄像头位置
    private func defaultCameraOverlayForFullScreen(_ screenSize: CGSize) -> CameraOverlayLayout {
        let side = min(max(screenSize.width * 0.15, 140), 220)
        let margin: CGFloat = 24
        return CameraOverlayLayout(
            origin: CGPoint(
                x: screenSize.width  - side - margin,
                y: screenSize.height - side - margin
            ),
            size: CGSize(width: side, height: side),
            style: .creatorDefault
        )
    }

    public func refreshWindows() async {
        do {
            let windows = try await captureService.availableWindows()
            availableWindows = windows
        } catch {
            availableWindows = []
        }
    }

    public func selectWindowSource(_ window: WindowSource?) {
        selectedWindowSource = window
        if let window {
            // 同步 captureRegion 以便 UI 显示
            let region = CaptureRegion(origin: window.frame.origin, size: window.frame.size)
            captureRegion = region
        }
    }

    public var captureSourceLabel: String {
        if let win = selectedWindowSource {
            return win.displayName
        }
        return captureRegionLabel
    }

    public func toggleExportSheet() {
        exportSheetPresented.toggle()
    }

    public func toggleExportVariant(_ platform: PlatformKind) {
        exportSelection.toggle(platform)
    }

    public func toggleInspector() {
        inspectorPresented.toggle()
    }

    public func toggleRegionSelection() {
        regionSelectionActive.toggle()
    }

    public func setRegionSelection(active: Bool) {
        regionSelectionActive = active
    }

    public func updateCaptureCanvasSize(_ canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        captureCanvasSize = canvasSize
        updateCaptureRegion(captureRegion, canvasSize: canvasSize)
    }

    public func updateCaptureRegion(_ region: CaptureRegion, canvasSize: CGSize) {
        captureCanvasSize = canvasSize
        let clampedRegion = region.clamped(to: canvasSize)
        captureRegion = clampedRegion
        cameraOverlay = cameraOverlay.clamped(to: clampedRegion)
    }

    public func updateCameraOverlay(_ overlay: CameraOverlayLayout) {
        cameraOverlay = overlay.clamped(to: captureRegion)
    }

    public func resizeCameraOverlay(by delta: CGSize) {
        cameraOverlay = cameraOverlay.resized(by: delta, in: captureRegion)
    }

    public func updateCameraShape(_ shape: CameraShape) {
        cameraOverlay = cameraOverlay.withShape(shape).clamped(to: captureRegion)
        // 实时同步到所有平台的 canvasLayout.pipShape，确保进入 Studio 时形状已最新
        for platform in PlatformKind.allCases {
            let key = platform.rawValue
            if canvasLayouts[key] != nil {
                canvasLayouts[key]!.pipShape = shape
            }
        }
        savePreferences()
    }

    public func resetCameraOverlay() {
        cameraOverlay = .default(in: captureRegion)
    }

    public func toggleCameraOverlay() {
        overlayState.cameraVisible.toggle()
        savePreferences()
    }

    public func toggleTeleprompterOverlay() {
        overlayState.teleprompterVisible.toggle()
        savePreferences()
    }

    public func toggleHUD() {
        overlayState.hudVisible.toggle()
        savePreferences()
    }

    public func toggleMicrophone() {
        overlayState.microphoneEnabled.toggle()
        savePreferences()
    }

    public func toggleSystemAudio() {
        overlayState.systemAudioEnabled.toggle()
        savePreferences()
    }

    // MARK: - 持久化属性 Setter（确保修改后触发保存）

    /// 更新提词器文本并自动保存
    public func updateTeleprompterText(_ text: String) {
        teleprompterText = text
        savePreferences()
    }

    /// 更新提词器滚动速度并自动保存
    public func updateTeleprompterScrollSpeed(_ speed: Double) {
        teleprompterScrollSpeed = speed
        savePreferences()
    }

    /// 更新 Smart Auto-Zoom 设置并自动保存（防抖写入，适合高频拖拽）
    public func updateSmartAutoZoomSettings(_ settings: SmartAutoZoomSettings) {
        smartAutoZoomSettings = settings
        savePreferences()
    }

    /// 更新摄像头美颜设置并自动保存（防抖写入，适合高频拖拽）
    public func updateCameraBeauty(_ beauty: CameraBeautySettings) {
        cameraBeauty = beauty
        savePreferences()
    }

    public func makeCaptureSessionConfiguration() -> CaptureSessionConfiguration {
        if let window = selectedWindowSource {
            return CaptureSessionConfiguration.fromWindow(
                window,
                on: selectedDisplaySource,
                cameraOverlay: overlayState.cameraVisible ? cameraOverlay : nil,
                microphoneEnabled: overlayState.microphoneEnabled,
                systemAudioEnabled: overlayState.systemAudioEnabled
            )
        }
        return CaptureSessionConfiguration(
            display: selectedDisplaySource,
            region: captureRegion,
            canvasSize: captureCanvasSize,
            cameraOverlay: overlayState.cameraVisible ? cameraOverlay : nil,
            microphoneEnabled: overlayState.microphoneEnabled,
            systemAudioEnabled: overlayState.systemAudioEnabled
        )
    }

    public func applyScreenSelection(_ selectionRect: CGRect) {
        let configuration = CaptureSessionConfiguration.fromScreenSelection(
            selectionRect,
            on: selectedDisplaySource,
            cameraOverlay: overlayState.cameraVisible ? cameraOverlay : nil,
            microphoneEnabled: overlayState.microphoneEnabled,
            systemAudioEnabled: overlayState.systemAudioEnabled
        )
        updateCaptureCanvasSize(configuration.canvasSize)
        updateCaptureRegion(configuration.region, canvasSize: configuration.canvasSize)
    }

    /// 最近一次录制启动失败的错误消息（用于 UI 层弹窗展示）
    public var recordingFailureMessage: String? = nil

    public func startRecordingSession() {
        guard !isRecordingActive else { return }

        recordedCursorClicks = []
        recordingState = .recording
        recordingFailureMessage = nil
        phase = .recording
        startElapsedTimer()
        let configuration = makeCaptureSessionConfiguration()

        Task { @MainActor in
            do {
                try await captureService.start(configuration: configuration)
            } catch {
                let msg = error.localizedDescription
                self.recordingState = .failed(msg)
                self.recordingFailureMessage = msg
                self.phase = .preparation
                self.stopElapsedTimer()
            }
        }
    }

    public func stopRecordingSession() async {
        guard isRecordingActive else { return }

        recordingState = .idle
        phase = .completion
        stopElapsedTimer()
        if var result = await captureService.stop() {
            // 将摄像头独立录像 URL 合并进结果
            result.cameraFileURL = pendingCameraFileURL
            result.cursorClickEvents = recordedCursorClicks
            latestRecording = result
        } else {
            latestRecording = nil
        }
        recordedCursorClicks = []
        pendingCameraFileURL = nil
        playbackState = .paused
        playbackPositionSeconds = 0
    }

    public func appendRecordedCursorClick(_ click: SmartAutoZoomClickEvent) {
        guard isRecordingActive else { return }
        recordedCursorClicks.append(click)
    }

    public func exportSelectedVariants() async {
        guard let latestRecording else {
            exportState = .failed("No recording available for export.")
            return
        }

        let variants = exportSelection.enabledVariants
        guard !variants.isEmpty else {
            exportState = .failed("Select at least one platform to export.")
            return
        }

        exportState = .exporting
        // 收集各平台画布布局
        let layoutsByPlatform: [String: CanvasLayout] = canvasLayouts
        do {
            let results = try await exportService.export(
                recording: latestRecording,
                variants: variants,
                trimStart: trimStartSeconds,
                trimEnd: trimEndSeconds,
                canvasLayouts: layoutsByPlatform,
                smartAutoZoomSettings: smartAutoZoomSettings
            )
            exportState = .completed(results)
            exportSheetPresented = false
            playbackState = .paused
            playbackPositionSeconds = 0
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    public func exportSourceAssets() async {
        guard let latestRecording else {
            sourceExportState = .failed("No recording available for source export.")
            return
        }

        sourceExportState = .exporting
        do {
            let results = try await exportService.exportSourceAssets(recording: latestRecording)
            sourceExportState = .completed(results)
            exportSheetPresented = false
            playbackState = .paused
            playbackPositionSeconds = 0
        } catch {
            sourceExportState = .failed(error.localizedDescription)
        }
    }

    public func togglePlayback() {
        switch playbackState {
        case .paused:
            // 用 trimEnd（若有）作为有效终点，判断是否需要从头重来
            let effectiveEnd = trimEndSeconds ?? playbackDurationSeconds
            if shouldRestartPlaybackFromBeginning(
                currentTime: playbackPositionSeconds,
                duration: effectiveEnd
            ) {
                // 如果有 trim，从 trimStart 开始；否则从 0 开始
                playbackPositionSeconds = trimStartSeconds
            }
            playbackState = .playing
        case .playing:
            playbackState = .paused
        }
    }

    public func restartPlayback() {
        // 重新开始时，应该从 trim 入点而不是绝对 0
        playbackPositionSeconds = trimStartSeconds
        playbackState = .playing
    }

    public func handlePlaybackFinished() {
        playbackPositionSeconds = playbackDurationSeconds
        playbackState = .paused
    }

    public func updatePlaybackPosition(seconds: Double) {
        playbackPositionSeconds = min(max(seconds, 0), playbackDurationSeconds)
    }

    public func seekPlayback(toProgress progress: Double) {
        let clampedProgress = min(max(progress, 0), 1)
        updatePlaybackPosition(seconds: playbackDurationSeconds * clampedProgress)
    }

    public func formatPlaybackTime(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    public var recordingElapsedLabel: String {
        let m = recordingElapsedSeconds / 60
        let s = recordingElapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 设置裁剪区间（秒）
    public func setTrim(startSeconds: Double, endSeconds: Double?) {
        let duration = playbackDurationSeconds
        trimStartSeconds = max(0, min(startSeconds, duration))
        if let end = endSeconds {
            trimEndSeconds = max(trimStartSeconds + 0.5, min(end, duration))
        } else {
            trimEndSeconds = nil
        }
    }

    /// 当前裁剪后的有效时长（秒）
    public var trimmedDurationSeconds: Double {
        let end = trimEndSeconds ?? playbackDurationSeconds
        return max(0, end - trimStartSeconds)
    }

    public func redo() {
        guard phase == .completion else { return }
        resetRecordingWorkspaceState()
        phase = .preparation
    }

    /// 从任意阶段（含 .editing）重置录制工作区状态，回到 .preparation
    /// 与 redo() 不同，redo() 仅允许从 .completion 调用；
    /// startNewRecording() 专门用于 Studio 编辑器中「新建录制」场景
    public func startNewRecording() {
        resetRecordingWorkspaceState()
        phase = .preparation
    }

    /// 统一清理录制与编辑相关的所有工作区状态
    private func resetRecordingWorkspaceState() {
        latestRecording = nil
        recordingElapsedSeconds = 0
        exportState = .idle
        sourceExportState = .idle
        playbackState = .paused
        playbackPositionSeconds = 0
        exportSheetPresented = false
        trimStartSeconds = 0
        trimEndSeconds = nil
    }

    public func openInStudio() {
        let prepShape = cameraOverlay.style.shape
        let recW = captureRegion.size.width
        let recH = captureRegion.size.height
        // 录制选区的宽高比（实际内容比例）
        let recAR = recW > 0 && recH > 0 ? recW / recH : 16.0 / 9.0

        for platform in PlatformKind.allCases {
            let key = platform.rawValue
            let platAR = platform.aspectRatio  // W/H

            // ── 1. screenFrame：Aspect Fit（保持录制原始比例，自适应缩放进画布）──────
            // 录制内容比画布宽（横向进竖屏）→ 宽度填满，高度按比例缩小，上下留黑边
            // 录制内容比画布窄（竖向进横屏）→ 高度填满，宽度按比例缩小，左右留黑边
            let screenWidthRatio:  Double
            let screenHeightRatio: Double
            if recAR >= platAR {
                screenWidthRatio  = 1.0
                screenHeightRatio = min(Double(platAR) / Double(recAR), 1.0)
            } else {
                screenHeightRatio = 1.0
                screenWidthRatio  = min(Double(recAR) / Double(platAR), 1.0)
            }
            let screenFrame = CanvasElementFrame(
                centerX: 0.5, centerY: 0.5,
                widthRatio:  screenWidthRatio,
                heightRatio: screenHeightRatio
            )
            // 不自动裁剪，保留完整录制内容，用户可在 Studio 手动裁剪
            let screenCrop = ScreenCropRect.full

            // ── 2. pipFrame：把 cameraOverlay 坐标映射到画布归一化坐标 ──────────
            // screenFrame 垂直居中（centerY=0.5），PiP 坐标需映射到 screenFrame 区域内
            var pipFrame: CanvasElementFrame? = nil
            if overlayState.cameraVisible && recW > 0 && recH > 0 {
                let pipAR = Double(platAR)
                // PiP 中心相对于 captureRegion 的归一化位置（0-1）
                let relCX = (cameraOverlay.origin.x + cameraOverlay.size.width  / 2 - captureRegion.origin.x) / recW
                let relCY = (cameraOverlay.origin.y + cameraOverlay.size.height / 2 - captureRegion.origin.y) / recH
                // screenFrame 在画布中的实际范围
                let scrLeft = 0.5 - screenWidthRatio  / 2.0
                let scrTop  = 0.5 - screenHeightRatio / 2.0
                // PiP 画布坐标：映射到 screenFrame 区域
                let canvasCX = scrLeft + relCX * screenWidthRatio
                let canvasCY = scrTop  + relCY * screenHeightRatio
                // PiP 大小：以 captureRegion 宽度为基准，映射到 screenFrame 宽度
                let pipSizeRatio = cameraOverlay.size.width / recW
                let pipW = pipSizeRatio * screenWidthRatio
                let pipH = pipW * pipAR  // 像素正方形

                pipFrame = CanvasElementFrame(
                    centerX: canvasCX,
                    centerY: canvasCY,
                    widthRatio: max(0.05, min(pipW, 0.8)),
                    heightRatio: max(0.05, min(pipH, 0.8))
                )
            }

            // ── 3. 组装 layout ────────────────────────────────────────────────
            var layout = canvasLayouts[key] ?? CanvasLayout.defaultLayout(for: platform, hasPiP: overlayState.cameraVisible)
            layout.screenFrame = screenFrame
            layout.screenCrop  = screenCrop
            layout.pipShape = prepShape
            if let pf = pipFrame {
                layout.pipFrame = pf
            } else if !overlayState.cameraVisible {
                layout.pipFrame = nil
            }
            canvasLayouts[key] = layout
        }
        phase = .editing
        savePreferences()
    }

    private func startElapsedTimer() {
        recordingElapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordingElapsedSeconds += 1
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}

public func shouldRestartPlaybackFromBeginning(currentTime: Double, duration: Double) -> Bool {
    guard duration > 0 else { return false }
    return currentTime >= max(duration - 0.1, 0)
}
