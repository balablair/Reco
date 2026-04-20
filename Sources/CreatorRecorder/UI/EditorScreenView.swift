import AVFoundation
import AVKit
import SwiftUI
import CreatorRecorderKit

struct EditorScreenView: View {
    let viewModel: AppViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.96, green: 0.95, blue: 0.93), Color(red: 0.94, green: 0.92, blue: 0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.82), lineWidth: 2)
                .padding(54)
                .shadow(color: .black.opacity(0.16), radius: 46)

            PlatformPillView(selectedPlatform: viewModel.selectedPlatform) { platform in
                viewModel.select(platform: platform)
            }
            .padding(.top, 28)
            .padding(.trailing, 42)

            RecordingPreviewSurface(
                previewURL: viewModel.currentPreviewFileURL,
                selectedPlatform: viewModel.selectedPlatform,
                playbackState: viewModel.playbackState,
                playbackProgress: viewModel.playbackProgress,
                currentTimeLabel: viewModel.currentPlaybackTimeLabel,
                totalTimeLabel: viewModel.totalPlaybackTimeLabel,
                onTogglePlayback: viewModel.togglePlayback,
                onRestartPlayback: viewModel.restartPlayback,
                onSeekPlayback: viewModel.seekPlayback,
                onPlaybackTimeChange: viewModel.updatePlaybackPosition,
                playbackDurationSeconds: viewModel.playbackDurationSeconds
            )
            .frame(width: previewSize.width, height: previewSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }
                .frame(width: 96, height: 96)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 124)
                .padding(.bottom, 148)

            Capsule()
                .fill(Color.black.opacity(0.68))
                .frame(width: 118, height: 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 170)
                .padding(.bottom, 162)

            VStack {
                HStack {
                    GlassTag(text: "Desktop Variant Editing")
                    Spacer()
                    Text("The exported composition is adjusted directly on top of the desktop stage.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 54)
                .padding(.top, 34)
                Spacer()
            }

            if viewModel.inspectorPresented {
                VStack(spacing: 12) {
                    InspectorCard(title: "Canvas") {
                        InspectorRow(title: "Safe Area", value: viewModel.selectedPlatform.ratioLabel)
                        InspectorRow(title: "Crop", value: currentPreviewKind)
                    }
                    InspectorCard(title: "Recording") {
                        InspectorRow(title: "File", value: recordingFileName)
                        InspectorRow(title: "Duration", value: recordingDuration)
                        InspectorRow(title: "Size", value: recordingFileSize)
                    }
                    InspectorCard(title: "Camera") {
                        InspectorRow(title: "Shape", value: "Rounded Card")
                        InspectorRow(title: "Blur", value: "Enabled")
                        InspectorRow(title: "Shadow", value: "Soft")
                    }
                    HStack(spacing: 10) {
                        Button("Full Preview") {}
                            .buttonStyle(SecondaryPillButtonStyle())
                        Button("Export") {
                            viewModel.toggleExportSheet()
                        }
                        .buttonStyle(PrimaryPillButtonStyle())
                    }
                }
                .frame(width: 320)
                .padding(.trailing, 42)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingFileName: String {
        viewModel.currentPreviewFileName
    }

    private var recordingDuration: String {
        viewModel.totalPlaybackTimeLabel
    }

    private var recordingFileSize: String {
        guard let bytes = viewModel.latestRecording?.fileSizeBytes else { return "--" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var previewSize: CGSize {
        let aspectRatio = viewModel.selectedPlatform.aspectRatio
        let maxHeight: CGFloat = 500
        let width = min(maxHeight * aspectRatio, 380)
        return CGSize(width: width, height: maxHeight)
    }

    private var currentPreviewKind: String {
        viewModel.exportedVariantsByPlatform[viewModel.selectedPlatform] == nil ? "Source" : "Exported"
    }
}

private struct RecordingPreviewSurface: View {
    let previewURL: URL?
    let selectedPlatform: PlatformKind
    let playbackState: PlaybackState
    let playbackProgress: Double
    let currentTimeLabel: String
    let totalTimeLabel: String
    let onTogglePlayback: () -> Void
    let onRestartPlayback: () -> Void
    let onSeekPlayback: (Double) -> Void
    let onPlaybackTimeChange: (Double) -> Void
    let playbackDurationSeconds: Double
    @State private var player: AVPlayer?
    @State private var videoSize: CGSize = .init(width: 1920, height: 1080)
    @State private var timeObserver: Any?

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.93, green: 0.90, blue: 0.86))

            if let previewURL, FileManager.default.fileExists(atPath: previewURL.path) {
                GeometryReader { geometry in
                    PlayerView(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .onAppear {
                            configurePlayer(with: previewURL)
                        }
                        .onChange(of: previewURL) { _, newURL in
                            configurePlayer(with: newURL)
                        }
                        .onChange(of: playbackState) { _, state in
                            guard let player else { return }
                            switch state {
                            case .playing:
                                player.play()
                            case .paused:
                                player.pause()
                            }
                        }
                        .onDisappear {
                            if let timeObserver, let player {
                                player.removeTimeObserver(timeObserver)
                                self.timeObserver = nil
                            }
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                    Text("Latest Recording Preview")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Stop a capture to preview the recorded file here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 180)
                }
            }

            PlatformCropOverlay(platform: selectedPlatform, videoSize: videoSize)

            if previewURL != nil {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Text(currentTimeLabel)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                        Slider(
                            value: Binding(
                                get: { playbackProgress },
                                set: { newProgress in
                                    onSeekPlayback(newProgress)
                                    let targetSeconds = playbackDurationSeconds * newProgress
                                    player?.seek(to: CMTime(seconds: targetSeconds, preferredTimescale: 600))
                                }
                            ),
                            in: 0...1
                        )
                        .tint(.white)
                        Text(totalTimeLabel)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 10) {
                        Button(playbackState == .playing ? "Pause" : "Play") {
                            onTogglePlayback()
                        }
                        .buttonStyle(SecondaryPillButtonStyle())

                        Button("Replay") {
                            player?.seek(to: .zero)
                            onRestartPlayback()
                        }
                        .buttonStyle(PrimaryPillButtonStyle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 22, y: 8)
    }

    private func configurePlayer(with url: URL) {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let playbackTimeHandler = onPlaybackTimeChange
        let nextPlayer = AVPlayer(url: url)
        let observer = nextPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { time in
            playbackTimeHandler(time.seconds)
        }

        player = nextPlayer
        timeObserver = observer
        loadVideoSize(from: url)
        if playbackState == .playing {
            nextPlayer.play()
        }
    }

    private func loadVideoSize(from url: URL) {
        Task {
            let asset = AVAsset(url: url)
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let size = try? await track.load(.naturalSize)
                if let size, size.width > 0, size.height > 0 {
                    await MainActor.run { videoSize = size }
                }
            }
        }
    }
}

private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context _: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context _: Context) {
        nsView.player = player
    }
}

private struct PlatformCropOverlay: View {
    let platform: PlatformKind
    let videoSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let crop = PlatformPreviewCrop(videoSize: videoSize, platform: platform)
            let normalizedCrop = normalizedCropRect(cropRect: crop.cropRect, in: videoSize)
            let previewRect = CGRect(
                x: geometry.size.width * normalizedCrop.origin.x,
                y: geometry.size.height * normalizedCrop.origin.y,
                width: geometry.size.width * normalizedCrop.size.width,
                height: geometry.size.height * normalizedCrop.size.height
            )

            Color.clear
                .overlay {
                    Color.black.opacity(0.001)
                        .frame(width: previewRect.width, height: previewRect.height)
                        .position(x: previewRect.midX, y: previewRect.midY)
                }

            Rectangle()
                .stroke(Color.white, lineWidth: 1)
                .frame(width: previewRect.width, height: previewRect.height)
                .position(x: previewRect.midX, y: previewRect.midY)

            ForEach([0.33, 0.66], id: \.self) { ratio in
                Rectangle()
                    .stroke(Color.white.opacity(0.32), lineWidth: 0.5)
                    .frame(width: previewRect.width, height: previewRect.height * ratio)
                    .position(x: previewRect.midX, y: previewRect.minY + previewRect.height * ratio / 2)
            }

            ForEach([0.33, 0.66], id: \.self) { ratio in
                Rectangle()
                    .stroke(Color.white.opacity(0.32), lineWidth: 0.5)
                    .frame(width: previewRect.width * ratio, height: previewRect.height)
                    .position(x: previewRect.minX + previewRect.width * ratio / 2, y: previewRect.midY)
            }

            CornersOverlay(rect: previewRect)
                .stroke(Color.white, lineWidth: 2)
        }
    }

    private func normalizedCropRect(cropRect: CGRect, in videoSize: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(
            x: cropRect.origin.x / videoSize.width,
            y: cropRect.origin.y / videoSize.height,
            width: cropRect.size.width / videoSize.width,
            height: cropRect.size.height / videoSize.height
        )
    }
}

private struct CornersOverlay: Shape {
    let rect: CGRect

    func path(in _: CGRect) -> Path {
        var path = Path()
        let cornerLength: CGFloat = 16

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))

        return path
    }
}
