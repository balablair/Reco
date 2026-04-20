@preconcurrency import AVFoundation
import Foundation
#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

public protocol ScreenCaptureServicing: Sendable {
    func availableDisplays() async throws -> [DisplaySource]
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
        guard let display = content.displays.first(where: { $0.displayID == configuration.display.id }) else {
            throw ScreenCaptureServiceError.displayNotFound(configuration.display.id)
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let descriptor = ScreenStreamDescriptor(
            configuration: configuration,
            pointPixelScale: pointPixelScale(for: filter)
        )
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

        return LiveCaptureSession.make(
            filter: filter,
            streamConfiguration: streamConfiguration
        )
        #else
        throw ScreenCaptureServiceError.unsupportedPlatform
        #endif
    }

    func availableDisplays() async throws -> [DisplaySource] {
        #if canImport(ScreenCaptureKit)
        let content = try await SCShareableContent.current
        let displays = content.displays.enumerated().map { index, display in
            DisplaySource(
                id: display.displayID,
                name: "Display \(index + 1)",
                frame: display.frame,
                isPrimary: index == 0,
                pointPixelScale: 1
            )
        }
        return displays.isEmpty ? [.placeholder] : displays
        #else
        return [.placeholder]
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
protocol RecordingResultProducing: Sendable {
    func finishResult() async -> RecordingResult?
}

final class LiveCaptureSession: NSObject, CaptureSessionRunning, @unchecked Sendable {
    private let stream: SCStream
    private let recordingResultProducer: (any RecordingResultProducing)?

    private init(stream: SCStream, recordingResultProducer: (any RecordingResultProducing)?) {
        self.stream = stream
        self.recordingResultProducer = recordingResultProducer
    }

    static func make(
        filter: SCContentFilter,
        streamConfiguration: SCStreamConfiguration
    ) -> LiveCaptureSession {
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: nil)
        if #available(macOS 15.0, *) {
            let outputURL = RecordingFileFactory.makeOutputURL()
            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = outputURL
            recordingConfiguration.outputFileType = .mp4
            recordingConfiguration.videoCodecType = .h264
            let outputBox = RecordingOutputBox(outputURL: outputURL)
            let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: outputBox)
            do {
                try stream.addRecordingOutput(recordingOutput)
                outputBox.recordingOutput = recordingOutput
                return LiveCaptureSession(stream: stream, recordingResultProducer: outputBox)
            } catch {
            }
        }
        return LiveCaptureSession(stream: stream, recordingResultProducer: nil)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
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
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent("capture-\(UUID().uuidString).mp4")
    }
}

enum ScreenCaptureServiceError: LocalizedError {
    case displayNotFound(UInt32)
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case let .displayNotFound(displayID):
            return "Display \(displayID) is no longer available."
        case .unsupportedPlatform:
            return "Screen capture is unavailable on this platform."
        }
    }
}

public protocol PlatformExportServicing: Sendable {
    func export(recording: RecordingResult, variants: [PlatformVariant]) async throws -> [ExportedVariantResult]
}

public actor PlatformExportService: PlatformExportServicing {
    public init() {}

    public func export(recording: RecordingResult, variants: [PlatformVariant]) async throws -> [ExportedVariantResult] {
        var results: [ExportedVariantResult] = []
        for variant in variants {
            let result = try await exportVariant(recording: recording, variant: variant)
            results.append(result)
        }
        return results
    }

    private func exportVariant(recording: RecordingResult, variant: PlatformVariant) async throws -> ExportedVariantResult {
        let asset = AVURLAsset(url: recording.fileURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw PlatformExportError.videoTrackMissing
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let orientedSize = naturalSize.applying(preferredTransform)
        let sourceSize = CGSize(width: abs(orientedSize.width), height: abs(orientedSize.height))
        let crop = PlatformPreviewCrop(videoSize: sourceSize, platform: variant.platform)
        let renderSize = variant.platform.exportRenderSize

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw PlatformExportError.compositionTrackCreationFailed
        }

        let duration = try await asset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        let scaleX = renderSize.width / crop.cropRect.width
        let scaleY = renderSize.height / crop.cropRect.height
        let transform = preferredTransform
            .translatedBy(x: -crop.cropRect.minX, y: -crop.cropRect.minY)
            .scaledBy(x: scaleX, y: scaleY)
        layerInstruction.setTransform(transform, at: .zero)

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let outputURL = RecordingFileFactory.makeVariantOutputURL(for: variant.platform)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw PlatformExportError.exportSessionUnavailable
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        try await exportSessionAsync(exportSession)

        let exportedMetadata = try await loadExportedVideoMetadata(from: outputURL)
        if let validationError = PlatformExportValidator.validate(
            metadata: exportedMetadata,
            for: variant.platform,
            sourceDurationSeconds: recording.durationSeconds
        ) {
            throw validationError
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ExportedVariantResult(
            platform: variant.platform,
            fileURL: outputURL,
            renderSize: exportedMetadata.renderSize,
            fileSizeBytes: fileSize
        )
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

private extension RecordingFileFactory {
    static func makeVariantOutputURL(for platform: PlatformKind) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreatorRecorder/Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent("\(platform.rawValue)-\(UUID().uuidString).mp4")
    }
}
