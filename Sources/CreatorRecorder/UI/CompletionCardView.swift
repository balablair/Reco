import AppKit
import AVFoundation
import SwiftUI
import CreatorRecorderKit

struct CompletionCardView: View {
    @Bindable var viewModel: AppViewModel
    let onRedo: () -> Void
    let onExportSource: () -> Void
    let onOpenInStudio: () -> Void

    var thumbnailImage: NSImage? {
        Self.thumbnailImage(for: viewModel.latestRecording)
    }

    private var cardModel: RecordingCompletionCardModel {
        makeRecordingCompletionCardModel(
            recordingElapsedSeconds: viewModel.recordingElapsedSeconds,
            sourceExportState: viewModel.sourceExportState
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                thumbnailView

                VStack(alignment: .leading, spacing: 6) {
                    Text(cardModel.eyebrow)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Color.black.opacity(0.38))

                    Text(cardModel.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                secondaryButton(label: "重录", action: onRedo)
                secondaryButton(
                    label: cardModel.exportSourceButtonTitle,
                    action: onExportSource,
                    isEnabled: cardModel.exportSourceButtonEnabled
                )
            }

            Button(action: onOpenInStudio) {
                Text(cardModel.primaryActionTitle)
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.88))
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(width: 392)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.68), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 32, y: 12)
    }

    private var thumbnailView: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .overlay {
                    thumbnailContent
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                )
                .frame(width: 112, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(cardModel.durationLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.76))
                )
                .padding(8)
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailImage {
            Image(nsImage: thumbnailImage)
                .resizable()
                .scaledToFill()
                .overlay {
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.4),
                    Color.white.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.22))
            }
        }
    }

    private var cardBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Rectangle().fill(Color.white.opacity(0.22)))
    }

    private static func thumbnailImage(for recording: RecordingResult?) -> NSImage? {
        guard let recording,
              FileManager.default.fileExists(atPath: recording.fileURL.path) else {
            return nil
        }

        let asset = AVURLAsset(url: recording.fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 224, height: 160)

        let durationSeconds = max(recording.durationSeconds, 0)
        let captureSecond = min(max(durationSeconds * 0.12, 0), max(durationSeconds - 0.05, 0))
        let captureTime = CMTime(seconds: captureSecond, preferredTimescale: 600)

        guard let cgImage = try? generator.copyCGImage(at: captureTime, actualTime: nil) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    @ViewBuilder
    private func secondaryButton(
        label: String,
        action: @escaping () -> Void,
        isEnabled: Bool = true
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(isEnabled ? 0.26 : 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(isEnabled ? 0.4 : 0.26), lineWidth: 0.5)
                )
                .foregroundStyle(Color.black.opacity(isEnabled ? 0.72 : 0.38))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
