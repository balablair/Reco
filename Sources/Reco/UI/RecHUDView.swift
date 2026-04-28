import SwiftUI
import RecoKit

struct RecHUDView: View {
    @Bindable var viewModel: AppViewModel
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // REC 指示器
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#ff453a"))
                    .frame(width: 8, height: 8)
                    .opacity(blinkOpacity)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: blinkOpacity)
                    .onAppear { blinkOpacity = 0.3 }

                Text("REC")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#ff453a"))
            }

            // 计时器
            Text(viewModel.recordingElapsedLabel)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.85))

            hudSeparator

            // Stop 按钮
            Button(action: onStop) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.18)))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .fixedSize()
        .background(darkGlassBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    @State private var blinkOpacity: Double = 1.0

    private var hudSeparator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.25), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private var darkGlassBackground: some View {
        Rectangle()
            .fill(Color(red: 28/255, green: 28/255, blue: 30/255).opacity(0.78))
            .overlay(Rectangle().fill(.ultraThinMaterial.opacity(0.2)))
    }
}

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
