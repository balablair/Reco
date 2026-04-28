import SwiftUI
import RecoKit

struct RecordingScreenView: View {
    let viewModel: AppViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.84, green: 0.90, blue: 1.0), Color(red: 0.97, green: 0.96, blue: 0.94)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                .padding(42)
                .shadow(color: .black.opacity(0.2), radius: 50)

            VStack {
                HStack {
                    GlassTag(text: "Recording Area")
                    Spacer()
                    HStack(spacing: 8) {
                        Text(regionLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.black.opacity(0.56))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        Text("REC 00:13")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.88)))
                    }
                }
                .padding(58)

                Spacer()
            }

            VStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .frame(height: 72)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill(Color.white.opacity(0.28)).frame(width: 340, height: 10)
                            Capsule().fill(Color.white.opacity(0.18)).frame(width: 260, height: 10)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, 82)
                    .padding(.top, 68)
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 8) {
                        GlassTag(text: viewModel.overlayState.microphoneEnabled ? "Mic: On" : "Mic: Off")
                            .opacity(viewModel.overlayState.microphoneEnabled ? 1 : 0.42)
                        GlassTag(text: viewModel.overlayState.systemAudioEnabled ? "System: On" : "System: Off")
                            .opacity(viewModel.overlayState.systemAudioEnabled ? 1 : 0.42)
                    }
                    Spacer()
                }
                .padding(.horizontal, 66)
                .padding(.bottom, 32)
            }

            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                }
                .frame(width: 148, height: 148)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color.black.opacity(0.36))
                        .frame(width: 98, height: 24)
                        .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 84)
                .padding(.bottom, 124)

            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1)
                }
                .frame(width: 360, height: 54)
                .overlay {
                    HStack(spacing: 18) {
                        Circle().fill(Color.red).frame(width: 18, height: 18)
                        Circle().fill(Color.white.opacity(0.75)).frame(width: 28, height: 28)
                        Capsule().fill(Color.white.opacity(0.18)).frame(width: 58, height: 28)
                        Circle().fill(Color.white.opacity(0.75)).frame(width: 28, height: 28)
                        Circle().fill(Color.white.opacity(0.75)).frame(width: 28, height: 28)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var regionLabel: String {
        "\(Int(viewModel.captureRegion.size.width)) × \(Int(viewModel.captureRegion.size.height))"
    }
}
