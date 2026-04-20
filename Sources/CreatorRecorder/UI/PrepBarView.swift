import SwiftUI
import CreatorRecorderKit

struct PrepBarView: View {
    @Bindable var viewModel: AppViewModel
    let onRecord: () -> Void
    let onPickArea: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 状态点
            Circle()
                .fill(Color(hex: "#28cd41"))
                .frame(width: 8, height: 8)

            // 区域尺寸标签
            Text(viewModel.captureRegionLabel)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.85))
                .monospacedDigit()

            separator

            // 功能 chips
            chipButton(
                icon: cameraIcon,
                active: viewModel.overlayState.cameraVisible
            ) {
                viewModel.toggleCameraOverlay()
            }

            chipButton(
                icon: teleprompterIcon,
                active: viewModel.overlayState.teleprompterVisible
            ) {
                viewModel.toggleTeleprompterOverlay()
            }

            chipButton(
                icon: micIcon,
                active: viewModel.overlayState.microphoneEnabled
            ) {
                viewModel.toggleMicrophone()
            }

            chipButton(
                icon: pickAreaIcon,
                active: false
            ) {
                onPickArea()
            }

            separator

            // Record CTA
            Button(action: onRecord) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#ff3b30"))
                        .frame(width: 8, height: 8)
                    Text("Record")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(Color.black.opacity(0.82))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
        .background(glassBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 28, y: 10)
        .contextMenu {
            Button("Quit CreatorRecorder") { onQuit() }
        }
    }

    // MARK: - Sub-components

    private var separator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 20)
            .padding(.horizontal, 6)
    }

    private var glassBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Rectangle().fill(Color.white.opacity(0.25)))
    }

    @ViewBuilder
    private func chipButton(icon: some View, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(active ? Color.black.opacity(0.08) : Color.clear)
                )
                .foregroundStyle(active ? Color.black.opacity(0.85) : Color.black.opacity(0.55))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Icons (SF Symbols)

    private var cameraIcon: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 14, weight: .medium))
    }

    private var teleprompterIcon: some View {
        Image(systemName: "text.alignleft")
            .font(.system(size: 14, weight: .medium))
    }

    private var micIcon: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 14, weight: .medium))
    }

    private var pickAreaIcon: some View {
        Image(systemName: "crop")
            .font(.system(size: 14, weight: .medium))
    }
}

// 便捷颜色初始化
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
