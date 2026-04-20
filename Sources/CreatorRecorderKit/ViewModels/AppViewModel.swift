import Foundation
import CoreGraphics
import Observation

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
    public var latestRecording: RecordingResult?
    public var exportState: ExportState = .idle
    public var playbackState: PlaybackState = .paused
    public var playbackPositionSeconds: Double = 0
    public var recordingElapsedSeconds: Int = 0
    private var elapsedTimer: Timer?

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
    }

    public func transitionToPhase(_ newPhase: AppPhase) {
        guard !isRecordingActive || newPhase == .recording else { return }
        phase = newPhase
    }

    public func select(platform: PlatformKind) {
        selectedPlatform = platform
    }

    public var exportedVariantsByPlatform: [PlatformKind: ExportedVariantResult] {
        guard case let .completed(results) = exportState else { return [:] }
        return Dictionary(uniqueKeysWithValues: results.map { ($0.platform, $0) })
    }

    public var currentPreviewFileURL: URL? {
        exportedVariantsByPlatform[selectedPlatform]?.fileURL ?? latestRecording?.fileURL
    }

    public var currentPreviewFileName: String {
        currentPreviewFileURL?.lastPathComponent ?? "Pending"
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
        } catch {
            updateAvailableDisplays([])
        }
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
    }

    public func resetCameraOverlay() {
        cameraOverlay = .default(in: captureRegion)
    }

    public func toggleCameraOverlay() {
        overlayState.cameraVisible.toggle()
    }

    public func toggleTeleprompterOverlay() {
        overlayState.teleprompterVisible.toggle()
    }

    public func toggleHUD() {
        overlayState.hudVisible.toggle()
    }

    public func toggleMicrophone() {
        overlayState.microphoneEnabled.toggle()
    }

    public func toggleSystemAudio() {
        overlayState.systemAudioEnabled.toggle()
    }

    public func makeCaptureSessionConfiguration() -> CaptureSessionConfiguration {
        CaptureSessionConfiguration(
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

    public func startRecordingSession() {
        guard !isRecordingActive else { return }

        recordingState = .recording
        phase = .recording
        startElapsedTimer()
        let configuration = makeCaptureSessionConfiguration()

        Task { @MainActor in
            do {
                try await captureService.start(configuration: configuration)
            } catch {
                self.recordingState = .failed(error.localizedDescription)
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
        latestRecording = await captureService.stop()
        playbackState = .paused
        playbackPositionSeconds = 0
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
        do {
            let results = try await exportService.export(recording: latestRecording, variants: variants)
            exportState = .completed(results)
            exportSheetPresented = false
            playbackState = .paused
            playbackPositionSeconds = 0
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    public func togglePlayback() {
        switch playbackState {
        case .paused:
            playbackState = .playing
        case .playing:
            playbackState = .paused
        }
    }

    public func restartPlayback() {
        playbackPositionSeconds = 0
        playbackState = .playing
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

    public func redo() {
        guard phase == .completion else { return }
        latestRecording = nil
        recordingElapsedSeconds = 0
        exportState = .idle
        phase = .preparation
    }

    public func openInStudio() {
        phase = .editing
    }

    private func startElapsedTimer() {
        recordingElapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordingElapsedSeconds += 1
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
