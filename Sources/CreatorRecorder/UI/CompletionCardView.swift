import SwiftUI
import CreatorRecorderKit

struct CompletionCardView: View {
    @Bindable var viewModel: AppViewModel
    let onRedo: () -> Void
    let onTrim: () -> Void
    let onShare: () -> Void
    let onOpenInStudio: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // 缩略图
            thumbnailView

            // 元数据
            HStack {
                Text(metaLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
                Spacer()
            }

            // 次要操作
            HStack(spacing: 8) {
                secondaryButton(label: "Redo", systemImage: "arrow.uturn.left") { onRedo() }
                secondaryButton(label: "Trim", systemImage: "scissors") { onTrim() }
                secondaryButton(label: "Share", systemImage: "square.and.arrow.up") { onShare() }
            }

            // 主操作
            Button(action: onOpenInStudio) {
                HStack {
                    Text("Open in Studio")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 310)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 32, y: 12)
    }

    // MARK: - Sub-components

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(height: 80)

            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.38))
        }
    }

    private var cardBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Rectangle().fill(Color.white.opacity(0.3)))
    }

    @ViewBuilder
    private func secondaryButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.06)))
            .foregroundStyle(Color.black.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private var metaLabel: String {
        let duration = viewModel.formatPlaybackTime(Double(viewModel.recordingElapsedSeconds))
        if let recording = viewModel.latestRecording {
            let mb = recording.fileSizeBytes / 1_000_000
            return "\(duration) · \(mb) MB"
        }
        return duration
    }
}
