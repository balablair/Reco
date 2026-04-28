@preconcurrency import AVFoundation
import Foundation
#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

public protocol ScreenCaptureServicing: Sendable {
    func availableDisplays() async throws -> [DisplaySource]
    func availableWindows() async throws -> [WindowSource]
    func start(configuration: CaptureSessionConfiguration) async throws
    func stop() async -> RecordingResult?
}

protocol CaptureSessionRunning: Sendable {
    func start() async throws
    func stop() async -> RecordingResult?
}

protocol ScreenCaptureSessionBuilding: Sendable {
    func makeSession(for configuration: CaptureSessionConfiguration) async throws -> any CaptureSessionRunning
}

public actor ScreenCaptureService: ScreenCaptureServicing {
    private let sessionBuilder: any ScreenCaptureSessionBuilding
    private var currentSession: (any CaptureSessionRunning)?

    public init() {
        self.sessionBuilder = LiveScreenCaptureSessionBuilder()
    }

    init(sessionBuilder: any ScreenCaptureSessionBuilding) {
        self.sessionBuilder = sessionBuilder
    }

    public func availableDisplays() async throws -> [DisplaySource] {
        try await LiveScreenCaptureSessionBuilder().availableDisplays()
    }

    public func availableWindows() async throws -> [WindowSource] {
        try await LiveScreenCaptureSessionBuilder().availableWindows()
    }

    public func start(configuration: CaptureSessionConfiguration) async throws {
        guard currentSession == nil else { return }
        let session = try await sessionBuilder.makeSession(for: configuration)
        try await session.start()
        currentSession = session
    }

    public func stop() async -> RecordingResult? {
        guard let currentSession else { return nil }
        let result = await currentSession.stop()
        self.currentSession = nil
        return result
    }
}

struct LiveScreenCaptureSessionBuilder: ScreenCaptureSessionBuilding {
    func makeSession(for configuration: CaptureSessionConfiguration) async throws -> any CaptureSessionRunning {
        #if canImport(ScreenCaptureKit)
        let content = try await SCShareableContent.current

        let filter: SCContentFilter

        // 窗口录制模式
        if let windowSource = configuration.windowSource {
            guard let scWindow = content.windows.first(where: { $0.windowID == windowSource.id }) else {
                // 窗口可能已消失，降级到全屏区域录制
                guard let display = content.displays.first(where: { $0.displayID == configuration.display.id }) else {
                    throw ScreenCaptureServiceError.displayNotFound(configuration.display.id)
                }
                filter = SCContentFilter(display: display, excludingWindows: [])
                if #available(macOS 14.2, *) { filter.includeMenuBar = false }
                let descriptor = ScreenStreamDescriptor(configuration: configuration, pointPixelScale: pointPixelScale(for: filter))
                let streamCfg = buildStreamConfiguration(descriptor: descriptor, configuration: configuration)
                return try LiveCaptureSession.make(filter: filter, streamConfiguration: streamCfg)
            }
            // 专用窗口 filter
            filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let winSize = CGSize(
                width: max(scWindow.frame.width, 1),
                height: max(scWindow.frame.height, 1)
            )
            let streamCfg = SCStreamConfiguration()
            streamCfg.width = Int(winSize.width.rounded(.up))
            streamCfg.height = Int(winSize.height.rounded(.up))
            streamCfg.showsCursor = true
            streamCfg.queueDepth = 5
            if #available(macOS 13.0, *) {
                streamCfg.capturesAudio = configuration.systemAudioEnabled
                streamCfg.sampleRate = 48_000
                streamCfg.channelCount = 2
            }
            if #available(macOS 15.0, *) {
                streamCfg.captureMicrophone = configuration.microphoneEnabled
            }
            return try LiveCaptureSession.make(filter: filter, streamConfiguration: streamCfg)
        }

        // 普通区域录制模式
        guard let display = content.displays.first(where: { $0.displayID == configuration.display.id }) else {
            throw ScreenCaptureServiceError.displayNotFound(configuration.display.id)
        }

        // 排除本 App 自身的所有窗口（边框、HUD、摄像头浮窗等），防止它们被录进视频
        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        let ownWindows = content.windows.filter { win in
            guard let app = win.owningApplication else { return false }
            return (app.bundleIdentifier ?? "") == selfBundleID
        }
        filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let descriptor = ScreenStreamDescriptor(
            configuration: configuration,
            pointPixelScale: pointPixelScale(for: filter)
        )
        let streamConfiguration = buildStreamConfiguration(descriptor: descriptor, configuration: configuration)
        return try LiveCaptureSession.make(
            filter: filter,
            streamConfiguration: streamConfiguration
        )
        #else
        throw ScreenCaptureServiceError.unsupportedPlatform
        #endif
    }

    private func buildStreamConfiguration(
        descriptor: ScreenStreamDescriptor,
        configuration: CaptureSessionConfiguration
    ) -> SCStreamConfiguration {
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = Int(descriptor.outputSize.width.rounded(.up))
        streamConfiguration.height = Int(descriptor.outputSize.height.rounded(.up))
        streamConfiguration.sourceRect = descriptor.sourceRect
        streamConfiguration.showsCursor = descriptor.showsCursor
        streamConfiguration.queueDepth = descriptor.queueDepth
        if #available(macOS 13.0, *) {
            streamConfiguration.capturesAudio = descriptor.capturesAudio
            streamConfiguration.sampleRate = 48_000
            streamConfiguration.channelCount = 2
        }
        if #available(macOS 15.0, *) {
            streamConfiguration.captureMicrophone = descriptor.captureMicrophone
        }
        return streamConfiguration
    }

    func availableDisplays() async throws -> [DisplaySource] {
        #if canImport(ScreenCaptureKit)
        let content = try await SCShareableContent.current
        return availableDisplaySources(from: content.displays)
        #else
        return [.placeholder]
        #endif
    }

    func availableWindows() async throws -> [WindowSource] {
        #if canImport(ScreenCaptureKit)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = availableDisplaySources(from: content.displays)
        // 过滤掉系统 UI（菜单栏、Dock等）和本应用自身
        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        let sources: [WindowSource] = content.windows.compactMap { win in
            guard let app = win.owningApplication else { return nil }
            // 跳过没有标题/非活跃的小窗口
            guard win.frame.width > 80, win.frame.height > 60 else { return nil }
            let bundleID = app.bundleIdentifier ?? ""
            guard bundleID != selfBundleID else { return nil }
            // 跳过 Dock 和系统 UI
            let systemBundles = ["com.apple.dock", "com.apple.systemuiserver", "com.apple.WindowManager"]
            guard !systemBundles.contains(bundleID) else { return nil }
            guard let display = displays.first(where: { $0.frame.intersects(win.frame) })
                    ?? displays.first(where: { $0.isPrimary })
                    ?? displays.first else {
                return nil
            }

            return WindowSource(
                id: UInt32(win.windowID),
                appName: app.applicationName,
                windowTitle: win.title ?? "",
                frame: convertWindowFrameFromScreenCaptureKit(win.frame, on: display),
                appBundleID: bundleID
            )
        }
        return sources
        #else
        return []
        #endif
    }

    private func pointPixelScale(for filter: SCContentFilter) -> CGFloat {
        if #available(macOS 14.0, *) {
            return CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
        }
        return 1
    }
}

#if canImport(ScreenCaptureKit)
private func availableDisplaySources(from displays: [SCDisplay]) -> [DisplaySource] {
    let sources = displays.enumerated().map { index, display in
        DisplaySource(
            id: display.displayID,
            name: "Display \(index + 1)",
            frame: display.frame,
            isPrimary: index == 0,
            pointPixelScale: 1
        )
    }
    return sources.isEmpty ? [.placeholder] : sources
}
#endif

public func convertWindowFrameFromScreenCaptureKit(_ frame: CGRect, on display: DisplaySource) -> CGRect {
    CGRect(
        x: frame.minX,
        y: display.frame.maxY - frame.maxY,
        width: frame.width,
        height: frame.height
    )
}

#if canImport(ScreenCaptureKit)
protocol RecordingResultProducing: Sendable {
    func finishResult() async -> RecordingResult?
}

/// 空的音频 sink：仅用于让 SCStream 激活系统音频轨道
/// SCRecordingOutput 需要 stream 上有 audio output listener 才会把音频写入文件
final class AudioSinkOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // 不做任何处理，仅激活音频 pipeline
    }
}

final class LiveCaptureSession: NSObject, CaptureSessionRunning, @unchecked Sendable {
    private let stream: SCStream
    private let recordingResultProducer: (any RecordingResultProducing)?
    // 持有 audioSink 的引用，防止被提前释放
    private let audioSink: AudioSinkOutput?

    private init(stream: SCStream, recordingResultProducer: (any RecordingResultProducing)?, audioSink: AudioSinkOutput? = nil) {
        self.stream = stream
        self.recordingResultProducer = recordingResultProducer
        self.audioSink = audioSink
    }

    static func make(
        filter: SCContentFilter,
        streamConfiguration: SCStreamConfiguration
    ) throws -> LiveCaptureSession {
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: nil)

        // 如果开启了系统音频录制，添加一个空的 audio output listener
        // 这会激活 SCStream 的音频 pipeline，让 SCRecordingOutput 正确录入系统音频
        var audioSink: AudioSinkOutput? = nil
        if streamConfiguration.capturesAudio {
            let sink = AudioSinkOutput()
            let audioQueue = DispatchQueue(label: "screen.audio.sink", qos: .utility)
            try? stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: audioQueue)
            audioSink = sink
        }

        if #available(macOS 15.0, *) {
            let outputURL = RecordingFileFactory.makeOutputURL()
            NSLog("[CaptureSession] outputURL=%@", outputURL.path)
            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = outputURL
            recordingConfiguration.outputFileType = .mp4
            recordingConfiguration.videoCodecType = .h264
            let outputBox = RecordingOutputBox(outputURL: outputURL)
            let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: outputBox)
            do {
                try stream.addRecordingOutput(recordingOutput)
                NSLog("[CaptureSession] addRecordingOutput succeeded")
                outputBox.recordingOutput = recordingOutput
                return LiveCaptureSession(stream: stream, recordingResultProducer: outputBox, audioSink: audioSink)
            } catch {
                NSLog("[CaptureSession] addRecordingOutput FAILED: %@ (domain=%@ code=%ld)",
                      error.localizedDescription,
                      (error as NSError).domain,
                      (error as NSError).code)
                throw error
            }
        }
        // macOS 14：不支持 SCRecordingOutput，抛出明确错误
        throw ScreenCaptureServiceError.recordingOutputUnavailable
    }

    func start() async throws {
        NSLog("[CaptureSession] startCapture begin")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    NSLog("[CaptureSession] startCapture FAILED: %@ (domain=%@ code=%ld)",
                          error.localizedDescription,
                          (error as NSError).domain,
                          (error as NSError).code)
                    continuation.resume(throwing: error)
                } else {
                    NSLog("[CaptureSession] startCapture succeeded")
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func stop() async -> RecordingResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.stopCapture { _ in
                continuation.resume(returning: ())
            }
        }
        return await recordingResultProducer?.finishResult()
    }
}

@available(macOS 15.0, *)
final class RecordingOutputBox: NSObject, SCRecordingOutputDelegate, RecordingResultProducing, @unchecked Sendable {
    let outputURL: URL
    var recordingOutput: SCRecordingOutput?
    private var continuation: CheckedContinuation<RecordingResult?, Never>?
    private var cachedResult: RecordingResult?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func finishResult() async -> RecordingResult? {
        if let cachedResult {
            return cachedResult
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let result = RecordingResult(
            fileURL: outputURL,
            durationSeconds: CMTimeGetSeconds(recordingOutput.recordedDuration),
            fileSizeBytes: Int64(recordingOutput.recordedFileSize)
        )
        cachedResult = result
        continuation?.resume(returning: result)
        continuation = nil
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
#endif

private enum RecordingFileFactory {
    static func makeOutputURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreatorRecorder", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            NSLog("[RecordingFileFactory] created directory: %@", directory.path)
        } catch {
            NSLog("[RecordingFileFactory] FAILED to create directory: %@ (error: %@)",
                  directory.path, error.localizedDescription)
        }
        let url = directory.appendingPathComponent("capture-\(UUID().uuidString).mp4")
        // 测试能否在该目录创建文件
        do {
            try Data().write(to: url)
            try FileManager.default.removeItem(at: url)
            NSLog("[RecordingFileFactory] write test passed: %@", url.path)
        } catch {
            NSLog("[RecordingFileFactory] write test FAILED: %@ (error: %@)",
                  url.path, error.localizedDescription)
        }
        return url
    }
}

enum ScreenCaptureServiceError: LocalizedError {
    case displayNotFound(UInt32)
    case unsupportedPlatform
    case recordingOutputUnavailable
    case addRecordingOutputFailed(Error)

    var errorDescription: String? {
        switch self {
        case let .displayNotFound(displayID):
            return "Display \(displayID) is no longer available."
        case .unsupportedPlatform:
            return "Screen capture is unavailable on this platform."
        case .recordingOutputUnavailable:
            return "录制功能需要 macOS 15 或更高版本。"
        case let .addRecordingOutputFailed(error):
            return "无法初始化录制输出：\(error.localizedDescription)\n\n请前往「系统设置 → 隐私与安全性 → 录屏与系统录音」确认权限已开启，并重启 App 后重试。"
        }
    }
}

public protocol PlatformExportServicing: Sendable {
    func export(
        recording: RecordingResult,
        variants: [PlatformVariant],
        trimStart: Double,
        trimEnd: Double?,
        canvasLayouts: [String: CanvasLayout],
        smartAutoZoomSettings: SmartAutoZoomSettings
    ) async throws -> [ExportedVariantResult]

    func exportSourceAssets(recording: RecordingResult) async throws -> [ExportedSourceAsset]
}

public actor PlatformExportService: PlatformExportServicing {
    public init() {}

    public func export(
        recording: RecordingResult,
        variants: [PlatformVariant],
        trimStart: Double = 0,
        trimEnd: Double? = nil,
        canvasLayouts: [String: CanvasLayout] = [:],
        smartAutoZoomSettings: SmartAutoZoomSettings = SmartAutoZoomSettings()
    ) async throws -> [ExportedVariantResult] {
        var results: [ExportedVariantResult] = []
        for variant in variants {
            let layout = canvasLayouts[variant.platform.rawValue]
            let result = try await exportVariant(
                recording: recording,
                variant: variant,
                trimStart: trimStart,
                trimEnd: trimEnd,
                canvasLayout: layout,
                smartAutoZoomSettings: smartAutoZoomSettings
            )
            results.append(result)
        }
        return results
    }

    public func exportSourceAssets(recording: RecordingResult) async throws -> [ExportedSourceAsset] {
        var assets: [ExportedSourceAsset] = []

        let screenURL = try copySourceAsset(
            from: recording.fileURL,
            kind: .screen,
            preferredExtension: recording.fileURL.pathExtension
        )
        let screenSize = fileSizeBytes(at: screenURL)
        assets.append(ExportedSourceAsset(kind: .screen, fileURL: screenURL, fileSizeBytes: screenSize))

        if let cameraURL = recording.cameraFileURL,
           FileManager.default.fileExists(atPath: cameraURL.path) {
            let copiedCameraURL = try copySourceAsset(
                from: cameraURL,
                kind: .camera,
                preferredExtension: cameraURL.pathExtension
            )
            let cameraSize = fileSizeBytes(at: copiedCameraURL)
            assets.append(ExportedSourceAsset(kind: .camera, fileURL: copiedCameraURL, fileSizeBytes: cameraSize))
        }

        return assets
    }

    // MARK: - 两步导出架构
    //
    // Pass 1 (exportScreenPass)：
    //   • 输入：原始屏幕录像 (recording.fileURL)
    //   • 操作：按 canvasLayout 缩放/裁剪，放置到 renderSize 画布上，填充背景色
    //   • 输出：中间视频（背景 + 录屏，无 PiP）
    //   • 实现：纯 AVFoundation（instruction.backgroundColor + setTransform），不需要 CALayer
    //
    // Pass 2 (exportPipPass)，仅在有摄像头录像时执行：
    //   • 输入：Pass 1 的中间视频 + 摄像头录像 (recording.cameraFileURL)
    //   • 操作：把摄像头视频缩放到 pipFrame，叠在 Pass 1 视频上方
    //   • 圆角裁切：CALayer 只负责 PiP 区域，职责单一
    //   • 输出：最终视频

    private func exportVariant(
        recording: RecordingResult,
        variant: PlatformVariant,
        trimStart: Double,
        trimEnd: Double?,
        canvasLayout: CanvasLayout?,
        smartAutoZoomSettings: SmartAutoZoomSettings
    ) async throws -> ExportedVariantResult {
        let layout = canvasLayout ?? CanvasLayout.defaultLayout(for: variant.platform, hasPiP: false)
        let renderSize = variant.platform.exportRenderSize

        // 计算 trim 时间范围
        let asset = AVURLAsset(url: recording.fileURL)
        let fullDuration = try await asset.load(.duration)
        let fullSeconds = CMTimeGetSeconds(fullDuration)
        let startSeconds = max(0, trimStart)
        let endSeconds = min(trimEnd ?? fullSeconds, fullSeconds)
        let trimmedDuration = CMTime(seconds: max(0.1, endSeconds - startSeconds), preferredTimescale: 600)
        let timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: trimmedDuration
        )

        NSLog("[Export] platform=%@ renderSize=(%g x %g) trimStart=%g trimEnd=%g",
              variant.platform.rawValue, renderSize.width, renderSize.height, startSeconds, endSeconds)

        let trimmedClickEvents = trimSmartAutoZoomClicks(
            recording.cursorClickEvents,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            settings: smartAutoZoomSettings
        )

        // ── Pass 1：录屏 + 背景色 → 中间视频 ─────────────────────────────────
        let pass1URL = RecordingFileFactory.makeTempURL(suffix: "pass1")
        try await exportScreenPass(
            screenURL: recording.fileURL,
            layout: layout,
            renderSize: renderSize,
            timeRange: timeRange,
            trimmedDuration: trimmedDuration,
            autoZoomClicks: trimmedClickEvents,
            smartAutoZoomSettings: smartAutoZoomSettings,
            outputURL: pass1URL
        )
        NSLog("[Export] Pass 1 done: %@", pass1URL.lastPathComponent)

        // ── Pass 2（可选）：中间视频 + PiP ────────────────────────────────────
        let hasCameraFile: Bool
        if let camURL = recording.cameraFileURL {
            hasCameraFile = FileManager.default.fileExists(atPath: camURL.path)
        } else {
            hasCameraFile = false
        }

        let outputURL: URL
        if hasCameraFile,
           let cameraURL = recording.cameraFileURL,
           let pipFrame = layout.pipFrame {
            let pass2URL = RecordingFileFactory.makeVariantOutputURL(for: variant.platform)
            try await exportPipPass(
                baseURL: pass1URL,
                cameraURL: cameraURL,
                pipFrame: pipFrame,
                pipShape: layout.pipShape,
                background: layout.background,
                renderSize: renderSize,
                trimStart: timeRange.start,
                trimmedDuration: trimmedDuration,
                outputURL: pass2URL
            )
            // 【调试】保留 Pass 1 中间文件供检查（正式发布时恢复删除）
            // try? FileManager.default.removeItem(at: pass1URL)
            NSLog("[Debug] Pass1 中间文件保留在: %@", pass1URL.path)
            outputURL = pass2URL
            NSLog("[Export] Pass 2 done: %@", pass2URL.lastPathComponent)
        } else {
            // 无 PiP：直接把 Pass 1 重命名为最终输出
            let finalURL = RecordingFileFactory.makeVariantOutputURL(for: variant.platform)
            try FileManager.default.moveItem(at: pass1URL, to: finalURL)
            outputURL = finalURL
            NSLog("[Export] No PiP, using Pass 1 as final output")
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let exportedMeta = try await loadExportedVideoMetadata(from: outputURL)
        return ExportedVariantResult(
            platform: variant.platform,
            fileURL: outputURL,
            renderSize: exportedMeta.renderSize,
            fileSizeBytes: fileSize
        )
    }

    private func trimSmartAutoZoomClicks(
        _ clicks: [SmartAutoZoomClickEvent],
        startSeconds: Double,
        endSeconds: Double,
        settings: SmartAutoZoomSettings
    ) -> [SmartAutoZoomClickEvent] {
        guard settings.isEnabled, endSeconds > startSeconds else { return [] }

        let effectLeadIn = max(settings.leadInSeconds, 0)
        let effectTail = max(settings.holdSeconds, 0) + max(settings.releaseSeconds, 0)

        return clicks.compactMap { click in
            let effectStart = click.timestampSeconds - effectLeadIn
            let effectEnd = click.timestampSeconds + effectTail
            guard effectEnd >= startSeconds, effectStart <= endSeconds else { return nil }
            return SmartAutoZoomClickEvent(
                timestampSeconds: click.timestampSeconds - startSeconds,
                normalizedX: click.normalizedX,
                normalizedY: click.normalizedY
            )
        }
    }

    // MARK: - Pass 1：录屏 + 背景色合成

    /// 将原始屏幕录像按 layout 放置到 renderSize 画布上，填充背景色，输出中间视频。
    /// Reader 只负责把源视频转成正方向帧；每帧的位置与裁剪由导出循环动态计算，确保 auto-zoom 与预览一致。
    private func exportScreenPass(
        screenURL: URL,
        layout: CanvasLayout,
        renderSize: CGSize,
        timeRange: CMTimeRange,
        trimmedDuration: CMTime,
        autoZoomClicks: [SmartAutoZoomClickEvent],
        smartAutoZoomSettings: SmartAutoZoomSettings,
        outputURL: URL
    ) async throws {
        let asset = AVURLAsset(url: screenURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw PlatformExportError.videoTrackMissing
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let orientedSize = naturalSize.applying(preferredTransform)
        let sourceSize = CGSize(width: abs(orientedSize.width), height: abs(orientedSize.height))

        NSLog("[Pass1] sourceSize=(%g x %g) renderSize=(%g x %g) screenFrame: cx=%g cy=%g w=%g h=%g",
              sourceSize.width, sourceSize.height,
              renderSize.width, renderSize.height,
              layout.screenFrame.centerX, layout.screenFrame.centerY,
              layout.screenFrame.widthRatio, layout.screenFrame.heightRatio)

        // 构建 composition
        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw PlatformExportError.compositionTrackCreationFailed }

        try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        compVideoTrack.preferredTransform = .identity   // 防止 transform 叠加

        // 音频轨道
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let compAudioTrack: AVMutableCompositionTrack?
        if let audioTrack = audioTracks.first,
           let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? track.insertTimeRange(timeRange, of: audioTrack, at: .zero)
            compAudioTrack = track
        } else {
            compAudioTrack = nil
        }

        let initialScreenGeometry = makeScreenPlacementGeometry(
            sourceSize: sourceSize,
            screenFrame: layout.screenFrame,
            crop: layout.screenCrop,
            renderSize: renderSize
        )

        NSLog("[Pass1] visibleRect=(%g,%g,%g,%g) fullRect=(%g,%g,%g,%g) tx=%g ty=%g scale=%g",
              initialScreenGeometry.visibleRect.minX, initialScreenGeometry.visibleRect.minY,
              initialScreenGeometry.visibleRect.width, initialScreenGeometry.visibleRect.height,
              initialScreenGeometry.fullRect.minX, initialScreenGeometry.fullRect.minY,
              initialScreenGeometry.fullRect.width, initialScreenGeometry.fullRect.height,
              initialScreenGeometry.tx, initialScreenGeometry.ty, initialScreenGeometry.scale)

        let orientationTransform = makePlacedTransform(
            base: preferredTransform,
            scale: 1,
            tx: 0,
            ty: 0
        )

        // VideoComposition：只负责把源视频转成正方向帧，后续几何由逐帧合成处理。
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = sourceSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: trimmedDuration)

        let screenInstr = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        screenInstr.setTransform(orientationTransform, at: .zero)
        instruction.layerInstructions = [screenInstr]

        // instruction.backgroundColor 设为透明，背景统一在逐帧合成时由 bgImage 叠底
        instruction.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        videoComposition.instructions = [instruction]

        // 使用 AVAssetWriter 强制输出目标 renderSize
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        // 用 PixelBufferAdaptor 写合成后的帧
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height)
            ]
        )
        writer.add(videoInput)

        // 音频 writer input
        var audioInput: AVAssetWriterInput? = nil
        if compAudioTrack != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = false
            writer.add(aInput)
            audioInput = aInput
        }

        // Reader：用 videoComposition 做变换，输出 BGRA 像素
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: trimmedDuration)

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [compVideoTrack],
            videoSettings: readerSettings
        )
        videoOutput.videoComposition = videoComposition
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)

        var readerAudioOutput: AVAssetReaderTrackOutput? = nil
        if let audioTrack = compAudioTrack {
            let aOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: exportAudioReaderOutputSettings()
            )
            aOutput.alwaysCopiesSampleData = false
            reader.add(aOutput)
            readerAudioOutput = aOutput
        }

        guard reader.startReading() else {
            throw reader.error ?? PlatformExportError.exportSessionUnavailable
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let w = Int(renderSize.width)
        let h = Int(renderSize.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "pass1.writer")
            var videoDone = false
            var audioDone = false

            func checkDone() {
                guard videoDone && audioDone else { return }
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: writer.error ?? PlatformExportError.exportSessionUnavailable)
                    }
                }
            }

            videoInput.requestMediaDataWhenReady(on: queue) {
                while videoInput.isReadyForMoreMediaData {
                    guard let sample = videoOutput.copyNextSampleBuffer() else {
                        videoInput.markAsFinished()
                        videoDone = true
                        checkDone()
                        return
                    }

                    // 从 sampleBuffer 取出视频帧的 CVPixelBuffer
                    guard let srcPixelBuf = CMSampleBufferGetImageBuffer(sample) else { continue }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)

                    guard let srcCGImage = makeCGImage(from: srcPixelBuf, colorSpace: colorSpace) else {
                        continue
                    }

                    let resolvedCrop = makeComposedSmartAutoZoomCrop(
                        baseCrop: layout.screenCrop,
                        at: CMTimeGetSeconds(pts),
                        clicks: autoZoomClicks,
                        durationSeconds: CMTimeGetSeconds(trimmedDuration),
                        settings: smartAutoZoomSettings
                    )
                    let screenGeometry = makeScreenPlacementGeometry(
                        sourceSize: sourceSize,
                        screenFrame: layout.screenFrame,
                        crop: resolvedCrop,
                        renderSize: renderSize
                    )
                    let screenClipPath = CGPath(
                        rect: renderRectInImageCoordinates(screenGeometry.visibleRect, canvasSize: renderSize),
                        transform: nil
                    )
                    let screenDrawRect = renderRectInImageCoordinates(screenGeometry.fullRect, canvasSize: renderSize)

                    guard let frameImage = compositeFrameImage(
                        canvasSize: renderSize,
                        background: layout.background,
                        overlayImage: srcCGImage,
                        overlayDrawRect: screenDrawRect,
                        overlayClipPath: screenClipPath
                    ) else {
                        continue
                    }

                    var outBuf: CVPixelBuffer?
                    let status = CVPixelBufferCreate(
                        kCFAllocatorDefault, w, h,
                        kCVPixelFormatType_32BGRA,
                        [kCVPixelBufferCGImageCompatibilityKey: true,
                         kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
                        &outBuf
                    )
                    guard status == kCVReturnSuccess, let outPixelBuf = outBuf else { continue }

                    CVPixelBufferLockBaseAddress(outPixelBuf, [])
                    let ctx = CGContext(
                        data: CVPixelBufferGetBaseAddress(outPixelBuf),
                        width: w, height: h,
                        bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(outPixelBuf),
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                    )
                    ctx?.draw(frameImage, in: CGRect(x: 0, y: 0, width: w, height: h))
                    CVPixelBufferUnlockBaseAddress(outPixelBuf, [])

                    adaptor.append(outPixelBuf, withPresentationTime: pts)
                }
            }

            if let aInput = audioInput, let aOutput = readerAudioOutput {
                aInput.requestMediaDataWhenReady(on: queue) {
                    while aInput.isReadyForMoreMediaData {
                        if let sample = aOutput.copyNextSampleBuffer() {
                            aInput.append(sample)
                        } else {
                            aInput.markAsFinished()
                            audioDone = true
                            checkDone()
                            return
                        }
                    }
                }
            } else {
                audioDone = true
            }
        }
    }

    /// 将 CanvasBackground 渲染为 CGImage（用于逐帧合成背景）
    /// 复用 makeBackgroundLayer，通过 CALayer 渲染到 CGContext，确保渐变方向与预览一致
    private func makeBackgroundImage(background: CanvasBackground, size: CGSize) -> CGImage? {
        let layer = makeBackgroundLayer(background: background, size: size)
        let w = Int(size.width)
        let h = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // CALayer 默认 Y-down，CGContext 默认 Y-up，需要翻转
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        layer.render(in: ctx)
        return ctx.makeImage()
    }

    // MARK: - Pass 2：在 Pass 1 视频上叠加 PiP

    /// 把 Pass 1 视频作为底图，逐帧合成 shape mask 后的 PiP。
    /// 这里不再用背景补片，而是直接把摄像头帧裁成真实形状后叠到底图上。
    private func exportPipPass(
        baseURL: URL,
        cameraURL: URL,
        pipFrame: CanvasElementFrame,
        pipShape: CameraShape,
        background: CanvasBackground,
        renderSize: CGSize,
        trimStart: CMTime,
        trimmedDuration: CMTime,
        outputURL: URL
    ) async throws {
        _ = background

        let baseAsset = AVURLAsset(url: baseURL)
        let cameraAsset = AVURLAsset(url: cameraURL)

        guard let baseVideoTrack = try await baseAsset.loadTracks(withMediaType: .video).first else {
            throw PlatformExportError.videoTrackMissing
        }
        guard let cameraVideoTrack = try await cameraAsset.loadTracks(withMediaType: .video).first else {
            try FileManager.default.copyItem(at: baseURL, to: outputURL)
            return
        }

        let baseDuration = try await baseAsset.load(.duration)
        let insertDuration = CMTimeMinimum(baseDuration, trimmedDuration)
        let cameraDuration = try await cameraAsset.load(.duration)
        guard let cameraTimeRange = pipSourceTimeRange(
            assetDuration: cameraDuration,
            trimStart: trimStart,
            trimmedDuration: trimmedDuration
        ) else {
            try FileManager.default.copyItem(at: baseURL, to: outputURL)
            return
        }
        let cameraInsertDuration = cameraTimeRange.duration

        let camNaturalSize = try await cameraVideoTrack.load(.naturalSize)
        let camPreferredTransform = try await cameraVideoTrack.load(.preferredTransform)
        let camOrientedSize = camNaturalSize.applying(camPreferredTransform)
        let camSize = CGSize(width: abs(camOrientedSize.width), height: abs(camOrientedSize.height))
        let pipGeometry = makePipPlacementGeometry(
            sourceSize: camSize,
            pipFrame: pipFrame,
            renderSize: renderSize
        )
        let pipClipRect = renderRectInImageCoordinates(pipGeometry.visibleRect, canvasSize: renderSize)
        let pipClipPath = makePipClipPath(shape: pipShape, rect: pipClipRect)

        NSLog("[Pass2] camSize=(%g x %g) pipRect=(%g %g %g %g) tx=%g ty=%g scale=%g",
              camSize.width, camSize.height,
              pipGeometry.visibleRect.minX, pipGeometry.visibleRect.minY,
              pipGeometry.visibleRect.width, pipGeometry.visibleRect.height,
              pipGeometry.tx, pipGeometry.ty, pipGeometry.scale)

        let cameraComposition = AVMutableComposition()
        guard let compCamTrack = cameraComposition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw PlatformExportError.compositionTrackCreationFailed }
        try compCamTrack.insertTimeRange(
            cameraTimeRange,
            of: cameraVideoTrack,
            at: .zero
        )
        compCamTrack.preferredTransform = .identity

        let cameraVideoComposition = AVMutableVideoComposition()
        cameraVideoComposition.renderSize = renderSize
        cameraVideoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let cameraInstruction = AVMutableVideoCompositionInstruction()
        cameraInstruction.timeRange = CMTimeRange(start: .zero, duration: cameraInsertDuration)
        cameraInstruction.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

        let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compCamTrack)
        cameraLayerInstruction.setTransform(
            makePlacedTransform(
                base: camPreferredTransform,
                scale: pipGeometry.scale,
                tx: pipGeometry.tx,
                ty: pipGeometry.ty
            ),
            at: .zero
        )
        cameraInstruction.layerInstructions = [cameraLayerInstruction]
        cameraVideoComposition.instructions = [cameraInstruction]

        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let baseReader = try AVAssetReader(asset: baseAsset)
        baseReader.timeRange = CMTimeRange(start: .zero, duration: insertDuration)
        let baseOutput = AVAssetReaderTrackOutput(track: baseVideoTrack, outputSettings: readerSettings)
        baseOutput.alwaysCopiesSampleData = false
        guard baseReader.canAdd(baseOutput) else {
            throw PlatformExportError.exportSessionUnavailable
        }
        baseReader.add(baseOutput)

        let cameraReader = try AVAssetReader(asset: cameraComposition)
        cameraReader.timeRange = CMTimeRange(start: .zero, duration: cameraInsertDuration)
        let cameraOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [compCamTrack],
            videoSettings: readerSettings
        )
        cameraOutput.videoComposition = cameraVideoComposition
        cameraOutput.alwaysCopiesSampleData = false
        guard cameraReader.canAdd(cameraOutput) else {
            throw PlatformExportError.exportSessionUnavailable
        }
        cameraReader.add(cameraOutput)

        let baseAudioTrack = try await baseAsset.loadTracks(withMediaType: .audio).first
        let cameraAudioTrack = try await cameraAsset.loadTracks(withMediaType: .audio).first
        let audioSource = preferredPipAudioSource(
            baseHasAudio: baseAudioTrack != nil,
            cameraHasAudio: cameraAudioTrack != nil
        )

        var audioReader: AVAssetReader?
        var audioOutput: AVAssetReaderTrackOutput?
        switch audioSource {
        case .camera:
            if let cameraAudioTrack {
                let reader = try AVAssetReader(asset: cameraAsset)
                reader.timeRange = cameraTimeRange
                let output = AVAssetReaderTrackOutput(
                    track: cameraAudioTrack,
                    outputSettings: exportAudioReaderOutputSettings()
                )
                output.alwaysCopiesSampleData = false
                guard reader.canAdd(output) else {
                    throw PlatformExportError.exportSessionUnavailable
                }
                reader.add(output)
                audioReader = reader
                audioOutput = output
            }
        case .base:
            if let baseAudioTrack {
                let reader = try AVAssetReader(asset: baseAsset)
                reader.timeRange = CMTimeRange(start: .zero, duration: insertDuration)
                let output = AVAssetReaderTrackOutput(
                    track: baseAudioTrack,
                    outputSettings: exportAudioReaderOutputSettings()
                )
                output.alwaysCopiesSampleData = false
                guard reader.canAdd(output) else {
                    throw PlatformExportError.exportSessionUnavailable
                }
                reader.add(output)
                audioReader = reader
                audioOutput = output
            }
        case .none:
            break
        }

        NSLog("[Pass2] audioSource=%@", String(describing: audioSource))

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height)
            ]
        )
        guard writer.canAdd(videoInput) else {
            throw PlatformExportError.exportSessionUnavailable
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw PlatformExportError.exportSessionUnavailable
            }
            writer.add(input)
            audioInput = input
        }

        guard baseReader.startReading() else {
            throw baseReader.error ?? PlatformExportError.exportSessionUnavailable
        }
        guard cameraReader.startReading() else {
            throw cameraReader.error ?? PlatformExportError.exportSessionUnavailable
        }
        if let audioReader {
            guard audioReader.startReading() else {
                throw audioReader.error ?? PlatformExportError.exportSessionUnavailable
            }
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fullRect = CGRect(origin: .zero, size: renderSize)
        let w = Int(renderSize.width)
        let h = Int(renderSize.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "pass2.writer")
            var videoDone = false
            var audioDone = audioInput == nil
            var latestCameraImage: CGImage?
            var nextCameraSample = cameraOutput.copyNextSampleBuffer()

            func checkDone() {
                guard videoDone && audioDone else { return }
                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: writer.error ?? PlatformExportError.exportSessionUnavailable)
                    }
                }
            }

            func advanceCameraFrame(for pts: CMTime) {
                while let sample = nextCameraSample {
                    let samplePTS = CMSampleBufferGetPresentationTimeStamp(sample)
                    if samplePTS > pts {
                        break
                    }
                    if let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
                        latestCameraImage = makeCGImage(from: pixelBuffer, colorSpace: colorSpace)
                    }
                    nextCameraSample = cameraOutput.copyNextSampleBuffer()
                }
            }

            videoInput.requestMediaDataWhenReady(on: queue) {
                while videoInput.isReadyForMoreMediaData {
                    guard let sample = baseOutput.copyNextSampleBuffer() else {
                        videoInput.markAsFinished()
                        videoDone = true
                        checkDone()
                        return
                    }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    advanceCameraFrame(for: pts)

                    guard let basePixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                    guard let baseImage = makeCGImage(from: basePixelBuffer, colorSpace: colorSpace) else { continue }

                    var outBuffer: CVPixelBuffer?
                    let status = CVPixelBufferCreate(
                        kCFAllocatorDefault,
                        w,
                        h,
                        kCVPixelFormatType_32BGRA,
                        [
                            kCVPixelBufferCGImageCompatibilityKey: true,
                            kCVPixelBufferCGBitmapContextCompatibilityKey: true
                        ] as CFDictionary,
                        &outBuffer
                    )
                    guard status == kCVReturnSuccess, let outputPixelBuffer = outBuffer else { continue }

                    guard let frameImage = compositeFrameImage(
                        canvasSize: renderSize,
                        backgroundImage: baseImage,
                        overlayImage: latestCameraImage,
                        overlayClipPath: pipClipPath
                    ) else {
                        continue
                    }

                    CVPixelBufferLockBaseAddress(outputPixelBuffer, [])
                    let ctx = CGContext(
                        data: CVPixelBufferGetBaseAddress(outputPixelBuffer),
                        width: w,
                        height: h,
                        bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(outputPixelBuffer),
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                    )
                    ctx?.draw(frameImage, in: fullRect)
                    CVPixelBufferUnlockBaseAddress(outputPixelBuffer, [])

                    adaptor.append(outputPixelBuffer, withPresentationTime: pts)
                }
            }

            if let audioInput, let audioOutput {
                audioInput.requestMediaDataWhenReady(on: queue) {
                    while audioInput.isReadyForMoreMediaData {
                        if let sample = audioOutput.copyNextSampleBuffer() {
                            audioInput.append(sample)
                        } else {
                            audioInput.markAsFinished()
                            audioDone = true
                            checkDone()
                            return
                        }
                    }
                }
            }
        }
    }

    /// 根据 CanvasBackground 创建 CALayer（用于渐变/图片背景）
    private func makeBackgroundLayer(background: CanvasBackground, size: CGSize) -> CALayer {
        let frame = CGRect(origin: .zero, size: size)
        switch background {
        case let .solidColor(r, g, b, a):
            let layer = CALayer()
            layer.frame = frame
            layer.backgroundColor = CGColor(red: r, green: g, blue: b, alpha: a)
            return layer

        case let .linearGradient(r1, g1, b1, r2, g2, b2, _):
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = frame
            gradientLayer.colors = [
                CGColor(red: r1, green: g1, blue: b1, alpha: 1),
                CGColor(red: r2, green: g2, blue: b2, alpha: 1)
            ]
            let points = background.gradientPointsForCoreAnimation()
            gradientLayer.startPoint = points?.start ?? CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = points?.end ?? CGPoint(x: 1, y: 1)
            return gradientLayer

        case let .image(path):
            let layer = CALayer()
            layer.frame = frame
            if let cgImage = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                layer.contents = cgImage
                layer.contentsGravity = .resizeAspectFill
            } else {
                layer.backgroundColor = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            }
            return layer
        }
    }
}

// MARK: - CanvasBackground → CGColor

extension CanvasBackground {
    /// 仅用于纯色背景的 instruction.backgroundColor 快速转换
    public func toCGColor() -> CGColor {
        switch self {
        case let .solidColor(r, g, b, a):
            return CGColor(red: r, green: g, blue: b, alpha: a)
        case let .linearGradient(r1, g1, b1, _, _, _, _):
            return CGColor(red: r1, green: g1, blue: b1, alpha: 1)
        case .image:
            return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
    }
}

public enum PlatformExportError: LocalizedError {
    case videoTrackMissing
    case compositionTrackCreationFailed
    case exportSessionUnavailable
    case exportedVideoTrackMissing

    public var errorDescription: String? {
        switch self {
        case .videoTrackMissing:
            return "The recording does not contain a video track."
        case .compositionTrackCreationFailed:
            return "Unable to create the composition track for export."
        case .exportSessionUnavailable:
            return "Unable to create the export session."
        case .exportedVideoTrackMissing:
            return "Unable to inspect the exported video track."
        }
    }
}

private func loadExportedVideoMetadata(from url: URL) async throws -> ExportedVideoMetadata {
    let asset = AVURLAsset(url: url)
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
        throw PlatformExportError.exportedVideoTrackMissing
    }

    let naturalSize = try await videoTrack.load(.naturalSize)
    let preferredTransform = try await videoTrack.load(.preferredTransform)
    let orientedSize = naturalSize.applying(preferredTransform)
    let renderSize = CGSize(width: abs(orientedSize.width), height: abs(orientedSize.height))
    let duration = try await asset.load(.duration)
    return ExportedVideoMetadata(renderSize: renderSize, durationSeconds: CMTimeGetSeconds(duration))
}

struct ExportPlacementGeometry: Equatable {
    let visibleRect: CGRect
    let fullRect: CGRect
    let scale: CGFloat
    let tx: CGFloat
    let ty: CGFloat
}

enum PIPAudioSourcePreference: Equatable {
    case base
    case camera
    case none
}

func preferredPipAudioSource(baseHasAudio: Bool, cameraHasAudio: Bool) -> PIPAudioSourcePreference {
    if cameraHasAudio {
        return .camera
    }
    if baseHasAudio {
        return .base
    }
    return .none
}

func pipSourceTimeRange(assetDuration: CMTime, trimStart: CMTime, trimmedDuration: CMTime) -> CMTimeRange? {
let safeTrimStart = max(trimStart.seconds, 0)
let safeDuration = max(trimmedDuration.seconds, 0)
let assetSeconds = max(assetDuration.seconds, 0)
guard safeTrimStart < assetSeconds, safeDuration > 0 else {
return nil
}

let duration = min(safeDuration, assetSeconds - safeTrimStart)
return CMTimeRange(
start: CMTime(seconds: safeTrimStart, preferredTimescale: 600),
duration: CMTime(seconds: duration, preferredTimescale: 600)
)
}

func exportAudioReaderOutputSettings() -> [String: Any] {
[
AVFormatIDKey: kAudioFormatLinearPCM,
AVLinearPCMBitDepthKey: 16,
AVLinearPCMIsBigEndianKey: false,
AVLinearPCMIsFloatKey: false,
AVLinearPCMIsNonInterleaved: false
]
}


func makeScreenPlacementGeometry(
    sourceSize: CGSize,
    screenFrame: CanvasElementFrame,
    crop: ScreenCropRect,
    renderSize: CGSize
) -> ExportPlacementGeometry {
    let visibleRect = screenFrame.toRect(in: renderSize)
    let fullRect = crop.contentRect(in: visibleRect)
    let scale = max(fullRect.width / max(sourceSize.width, 1), fullRect.height / max(sourceSize.height, 1))
    let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let tx = fullRect.minX + (fullRect.width - scaledSize.width) / 2
    let ty = fullRect.minY + (fullRect.height - scaledSize.height) / 2
    return ExportPlacementGeometry(
        visibleRect: visibleRect,
        fullRect: fullRect,
        scale: scale,
        tx: tx,
        ty: ty
    )
}

func makePipPlacementGeometry(
    sourceSize: CGSize,
    pipFrame: CanvasElementFrame,
    renderSize: CGSize
) -> ExportPlacementGeometry {
    let visibleRect = pipFrame.toRect(in: renderSize)
    let scale = max(visibleRect.width / max(sourceSize.width, 1), visibleRect.height / max(sourceSize.height, 1))
    let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let tx = visibleRect.minX + (visibleRect.width - scaledSize.width) / 2
    let ty = visibleRect.minY + (visibleRect.height - scaledSize.height) / 2
    return ExportPlacementGeometry(
        visibleRect: visibleRect,
        fullRect: visibleRect,
        scale: scale,
        tx: tx,
        ty: ty
    )
}

func makePlacedTransform(
    base: CGAffineTransform,
    scale: CGFloat,
    tx: CGFloat,
    ty: CGFloat
) -> CGAffineTransform {
    // AVFoundation setTransform 语义：源视频像素 → 渲染画布像素
    // 变换矩阵为：[scale  0    ] + 平移 (tx, ty)
    //             [0      scale]
    //
    // 正确构造：先对 base（处理视频旋转/翻转）应用 scale，再叠加平移
    // 不能用链式 .scaledBy().translatedBy()，因为 translatedBy 是在 scale
    // 之后的坐标系中操作，会导致平移量被再次 scale
    //
    // 等价于 CGAffineTransform(a: a*s, b: b*s, c: c*s, d: d*s, tx: tx, ty: ty)
    let safeScale = max(scale, 0.0001)
    return CGAffineTransform(
        a: base.a * safeScale,
        b: base.b * safeScale,
        c: base.c * safeScale,
        d: base.d * safeScale,
        tx: base.tx * safeScale + tx,
        ty: base.ty * safeScale + ty
    )
}

func renderRectInImageCoordinates(_ rect: CGRect, canvasSize: CGSize) -> CGRect {
    CGRect(
        x: rect.minX,
        y: canvasSize.height - rect.maxY,
        width: rect.width,
        height: rect.height
    )
}

private func makeCompositeContext(canvasSize: CGSize) -> CGContext? {
    let width = Int(canvasSize.width)
    let height = Int(canvasSize.height)
    guard width > 0, height > 0 else { return nil }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )
}

private func makeDeviceRGBColor(red: Double, green: Double, blue: Double, alpha: Double) -> CGColor {
    CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [red, green, blue, alpha]
    ) ?? CGColor(gray: 0, alpha: alpha)
}

private func drawCanvasBackground(_ background: CanvasBackground, in ctx: CGContext, rect: CGRect) {
    switch background {
    case let .solidColor(r, g, b, a):
        ctx.saveGState()
        ctx.setFillColor(makeDeviceRGBColor(red: r, green: g, blue: b, alpha: a))
        ctx.fill(rect)
        ctx.restoreGState()

    case let .linearGradient(r1, g1, b1, r2, g2, b2, _):
        let colors = [
            makeDeviceRGBColor(red: r1, green: g1, blue: b1, alpha: 1),
            makeDeviceRGBColor(red: r2, green: g2, blue: b2, alpha: 1)
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else {
            return
        }
        let points = background.gradientPointsForCoreAnimation()
        let start = CGPoint(
            x: rect.minX + (points?.start.x ?? 0) * rect.width,
            y: rect.minY + (points?.start.y ?? 0) * rect.height
        )
        let end = CGPoint(
            x: rect.minX + (points?.end.x ?? 1) * rect.width,
            y: rect.minY + (points?.end.y ?? 1) * rect.height
        )
        ctx.saveGState()
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()

    case let .image(path):
        ctx.saveGState()
        if let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let imageSize = CGSize(width: image.width, height: image.height)
            let scale = max(rect.width / max(imageSize.width, 1), rect.height / max(imageSize.height, 1))
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let drawRect = CGRect(
                x: rect.minX + (rect.width - drawSize.width) / 2,
                y: rect.minY + (rect.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            ctx.draw(image, in: drawRect)
        } else {
            ctx.setFillColor(makeDeviceRGBColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            ctx.fill(rect)
        }
        ctx.restoreGState()
    }
}

func compositeFrameImage(
    canvasSize: CGSize,
    background: CanvasBackground,
    overlayImage: CGImage?,
    overlayClipPath: CGPath?
) -> CGImage? {
    compositeFrameImage(
        canvasSize: canvasSize,
        background: background,
        overlayImage: overlayImage,
        overlayDrawRect: CGRect(origin: .zero, size: canvasSize),
        overlayClipPath: overlayClipPath
    )
}

func compositeFrameImage(
    canvasSize: CGSize,
    background: CanvasBackground,
    overlayImage: CGImage?,
    overlayDrawRect: CGRect,
    overlayClipPath: CGPath?
) -> CGImage? {
    guard let ctx = makeCompositeContext(canvasSize: canvasSize) else {
        return nil
    }

    let fullRect = CGRect(origin: .zero, size: canvasSize)
    drawCanvasBackground(background, in: ctx, rect: fullRect)
    if let overlayImage {
        ctx.saveGState()
        if let overlayClipPath {
            ctx.addPath(overlayClipPath)
            ctx.clip()
        }
        ctx.draw(overlayImage, in: overlayDrawRect)
        ctx.restoreGState()
    }
    return ctx.makeImage()
}

func compositeFrameImage(
    canvasSize: CGSize,
    backgroundImage: CGImage?,
    overlayImage: CGImage?,
    overlayClipPath: CGPath?
) -> CGImage? {
    guard let ctx = makeCompositeContext(canvasSize: canvasSize) else {
        return nil
    }

    let fullRect = CGRect(origin: .zero, size: canvasSize)
    if let backgroundImage {
        ctx.draw(backgroundImage, in: fullRect)
    }
    if let overlayImage {
        ctx.saveGState()
        if let overlayClipPath {
            ctx.addPath(overlayClipPath)
            ctx.clip()
        }
        ctx.draw(overlayImage, in: fullRect)
        ctx.restoreGState()
    }
    return ctx.makeImage()
}

private func makeCGImage(from pixelBuffer: CVPixelBuffer, colorSpace: CGColorSpace) -> CGImage? {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: CVPixelBufferGetWidth(pixelBuffer),
        height: CVPixelBufferGetHeight(pixelBuffer),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
        return nil
    }
    return ctx.makeImage()
}

private func exportSessionAsync(_ exportSession: AVAssetExportSession) async throws {
    try await withCheckedThrowingContinuation { continuation in
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                continuation.resume(returning: ())
            case .failed, .cancelled:
                continuation.resume(throwing: exportSession.error ?? PlatformExportError.exportSessionUnavailable)
            default:
                continuation.resume(throwing: PlatformExportError.exportSessionUnavailable)
            }
        }
    }
}

private func fileSizeBytes(at url: URL) -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
}

private func copySourceAsset(from sourceURL: URL, kind: SourceAssetKind, preferredExtension: String) throws -> URL {
    let pathExtension = preferredExtension.isEmpty ? "mp4" : preferredExtension
    let destinationURL = RecordingFileFactory.makeSourceAssetOutputURL(kind: kind, pathExtension: pathExtension)
    try? FileManager.default.removeItem(at: destinationURL)
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    return destinationURL
}

private extension RecordingFileFactory {
    static func makeVariantOutputURL(for platform: PlatformKind) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreatorRecorder/Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent("\(platform.rawValue)-\(UUID().uuidString).mp4")
    }

    static func makeSourceAssetOutputURL(kind: SourceAssetKind, pathExtension: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreatorRecorder/Exports/SourceAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent("\(kind.rawValue)-\(UUID().uuidString).\(pathExtension)")
    }

    /// 创建临时中间文件 URL（两步导出架构用）
    static func makeTempURL(suffix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreatorRecorder/Temp", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent("\(suffix)-\(UUID().uuidString).mp4")
    }
}
